# frozen_string_literal: true

require 'rubystats'

module Split
  class Experiment
    attr_accessor :name
    attr_accessor :goals
    attr_accessor :alternative_probabilities
    attr_accessor :metadata
    attr_accessor :friendly_name

    attr_reader :alternatives
    attr_reader :resettable
    attr_reader :retain_user_alternatives_after_reset

    DEFAULT_OPTIONS = {
      :resettable => true,
      :retain_user_alternatives_after_reset => false,
    }

    def self.find(name)
      Split.cache(:experiments, name) do
        return unless Split.redis.exists?(name)
        Experiment.new(name).tap { |exp| exp.load_from_redis }
      end
    end

    def initialize(name, options = {})
      options = DEFAULT_OPTIONS.merge(options)

      @name = name.to_s

      extract_alternatives_from_options(options)
    end

    def self.finished_key(key)
      "#{key}:finished"
    end

    def set_alternatives_and_options(options)
      options_with_defaults = DEFAULT_OPTIONS.merge(
        options.reject { |k, v| v.nil? }
      )

      self.alternatives = options_with_defaults[:alternatives]
      self.goals = options_with_defaults[:goals]
      self.resettable = options_with_defaults[:resettable]
      self.algorithm = options_with_defaults[:algorithm]
      self.metadata = options_with_defaults[:metadata]
      self.friendly_name = options_with_defaults[:friendly_name] || @name
      self.retain_user_alternatives_after_reset = options_with_defaults[:retain_user_alternatives_after_reset]
    end

    def extract_alternatives_from_options(options)
      alts = options[:alternatives] || []

      if alts.length == 1
        if alts[0].is_a? Hash
          alts = alts[0].map{|k,v| {k => v} }
        end
      end

      if alts.empty?
        exp_config = Split.configuration.experiment_for(name)
        if exp_config
          alts = load_alternatives_from_configuration
          options[:goals] = Split::GoalsCollection.new(@name).load_from_configuration
          options[:metadata] = load_metadata_from_configuration
          options[:resettable] = exp_config[:resettable]
          options[:algorithm] = exp_config[:algorithm]
          options[:friendly_name] = exp_config[:friendly_name]
          options[:retain_user_alternatives_after_reset] = exp_config[:retain_user_alternatives_after_reset]
        end
      end

      options[:alternatives] = alts

      set_alternatives_and_options(options)

      # calculate probability that each alternative is the winner
      @alternative_probabilities = {}
      alts
    end

    def save
      validate!

      if new_record?
        start unless Split.configuration.start_manually
        persist_experiment_configuration
      elsif experiment_configuration_has_changed?
        reset unless Split.configuration.reset_manually
        persist_experiment_configuration
      end

      redis.hmset(experiment_config_key,
                 :resettable, resettable.to_s,
                 :algorithm, algorithm.to_s,
                 :retain_user_alternatives_after_reset, retain_user_alternatives_after_reset.to_s)
      self
    end

    def validate!
      if @alternatives.empty? && Split.configuration.experiment_for(@name).nil?
        raise ExperimentNotFound.new("Experiment #{@name} not found")
      end
      @alternatives.each {|a| a.validate! }
      goals_collection.validate!
    end

    def new_record?
      !redis.exists?(name)
    end

    def ==(obj)
      self.name == obj.name
    end

    def [](name)
      alternatives.find{|a| a.name == name}
    end

    def algorithm
      @algorithm ||= Split.configuration.algorithm
    end

    def algorithm=(algorithm)
      @algorithm = algorithm.is_a?(String) ? algorithm.constantize : algorithm
    end

    def resettable=(resettable)
      @resettable = resettable.is_a?(String) ? resettable == "true" : resettable
    end

    def retain_user_alternatives_after_reset=(value)
      @retain_user_alternatives_after_reset = value.is_a?(String) ? value == "true" : value
    end

    def alternatives=(alts)
      @alternatives = alts.map do |alternative|
        if alternative.kind_of?(Split::Alternative)
          alternative
        else
          Split::Alternative.new(alternative, @name)
        end
      end
    end

    def winner
      experiment_winner = redis.hget(:experiment_winner, name)
      if experiment_winner
        Split::Alternative.new(experiment_winner, name)
      else
        nil
      end
    end

    def has_winner?
      return @has_winner if defined? @has_winner
      @has_winner = !winner.nil?
    end

    def winner=(winner_name)
      redis.hset(:experiment_winner, name, winner_name.to_s)
      @has_winner = true
      Split.configuration.on_experiment_winner_choose.call(self)
    end

    def participant_count
      alternatives.inject(0){|sum,a| sum + a.participant_count}
    end

    def control
      alternatives.first
    end

    def reset_winner
      redis.hdel(:experiment_winner, name)
      @has_winner = false
    end

    def start
      redis.hset(:experiment_start_times, @name, Time.now.to_i)
    end

    def start_time
      t = redis.hget(:experiment_start_times, @name)
      if t
        # Check if stored time is an integer
        if t =~ /^[-+]?[0-9]+$/
          Time.at(t.to_i)
        else
          Time.parse(t)
        end
      end
    end

    def next_alternative
      winner || random_alternative
    end

    def random_alternative
      if alternatives.length > 1
        algorithm.choose_alternative(self)
      else
        alternatives.first
      end
    end

    def version
      @version ||= (redis.get("#{name}:version").to_i || 0)
    end

    def increment_version
      @version = redis.incr("#{name}:version")
    end

    def key
      if version.to_i > 0
        "#{name}:#{version}"
      else
        name
      end
    end

    def goals_key
      "#{name}:goals"
    end

    def finished_key
      self.class.finished_key(key)
    end

    def metadata_key
      "#{name}:metadata"
    end

    def friendly_name_key
      "#{name}:friendly_name"
    end

    def resettable?
      resettable
    end

    def reset
      Split.configuration.on_before_experiment_reset.call(self)
      alternatives.each(&:reset)
      reset_winner
      Split.configuration.on_experiment_reset.call(self)
      increment_version
    end

    def delete
      Split.configuration.on_before_experiment_delete.call(self)
      if Split.configuration.start_manually
        redis.hdel(:experiment_start_times, @name)
      end
      reset_winner
      redis.srem(:experiments, name)
      redis.hdel(experiment_config_key, :cohorting)
      remove_experiment_cohorting
      remove_experiment_configuration
      Split.configuration.on_experiment_delete.call(self)
      increment_version
    end

    def delete_metadata
      redis.del(metadata_key)
    end

    def load_from_redis
      exp_config = redis.hgetall(experiment_config_key)

      options = {
        retain_user_alternatives_after_reset: exp_config["retain_user_alternatives_after_reset"],
        resettable: exp_config["resettable"],
        algorithm: exp_config["algorithm"],
        friendly_name: load_friendly_name_from_redis,
        alternatives: load_alternatives_from_redis,
        goals: Split::GoalsCollection.new(@name).load_from_redis,
        metadata: load_metadata_from_redis
      }

      set_alternatives_and_options(options)
    end

    def can_calculate_winning_alternatives?
      self.alternatives.all? do |alternative|
        alternative.participant_count >= 0 &&
        (alternative.participant_count >= alternative.completed_count)
      end
    end

    def calc_winning_alternatives
      return unless can_calculate_winning_alternatives?

      # Cache the winning alternatives so we recalculate them once per the specified interval.
      intervals_since_epoch =
        Time.now.utc.to_i / Split.configuration.winning_alternative_recalculation_interval

      if self.calc_time != intervals_since_epoch
        if goals.empty?
          self.estimate_winning_alternative
        else
          goals.each do |goal|
            self.estimate_winning_alternative(goal)
          end
        end

        self.calc_time = intervals_since_epoch

        self.save
      end
    end

    def estimate_winning_alternative(goal = nil)
      # initialize a hash of beta distributions based on the alternatives' conversion rates
      beta_params = calc_beta_params(goal)

      winning_alternatives = []

      Split.configuration.beta_probability_simulations.times do
        # calculate simulated conversion rates from the beta distributions
        simulated_cr_hash = calc_simulated_conversion_rates(beta_params)

        winning_alternative = find_simulated_winner(simulated_cr_hash)

        # push the winning pair to the winning_alternatives array
        winning_alternatives.push(winning_alternative)
      end

      winning_counts = count_simulated_wins(winning_alternatives)

      @alternative_probabilities = calc_alternative_probabilities(winning_counts, Split.configuration.beta_probability_simulations)

      write_to_alternatives(goal)

      self.save
    end

    def write_to_alternatives(goal = nil)
      alternatives.each do |alternative|
        alternative.set_p_winner(@alternative_probabilities[alternative], goal)
      end
    end

    def calc_alternative_probabilities(winning_counts, number_of_simulations)
      alternative_probabilities = {}
      winning_counts.each do |alternative, wins|
        alternative_probabilities[alternative] = wins / number_of_simulations.to_f
      end
      return alternative_probabilities
    end

    def count_simulated_wins(winning_alternatives)
       # initialize a hash to keep track of winning alternative in simulations
      winning_counts = {}
      alternatives.each do |alternative|
        winning_counts[alternative] = 0
      end
      # count number of times each alternative won, calculate probabilities, place in hash
      winning_alternatives.each do |alternative|
        winning_counts[alternative] += 1
      end
      return winning_counts
    end

    def find_simulated_winner(simulated_cr_hash)
      # figure out which alternative had the highest simulated conversion rate
      winning_pair = ["",0.0]
      simulated_cr_hash.each do |alternative, rate|
        if rate > winning_pair[1]
          winning_pair = [alternative, rate]
        end
      end
      winner = winning_pair[0]
      return winner
    end

    def calc_simulated_conversion_rates(beta_params)
      simulated_cr_hash = {}

      # create a hash which has the conversion rate pulled from each alternative's beta distribution
      beta_params.each do |alternative, params|
        alpha = params[0]
        beta = params[1]
        simulated_conversion_rate = Rubystats::BetaDistribution.new(alpha, beta).rng
        simulated_cr_hash[alternative] = simulated_conversion_rate
      end

      return simulated_cr_hash
    end

    def calc_beta_params(goal = nil)
      beta_params = {}
      alternatives.each do |alternative|
        conversions = goal.nil? ? alternative.completed_count : alternative.completed_count(goal)
        alpha = 1 + conversions
        beta = 1 + alternative.participant_count - conversions

        params = [alpha, beta]

        beta_params[alternative] = params
      end
      return beta_params
    end

    def calc_time=(time)
      redis.hset(experiment_config_key, :calc_time, time)
    end

    def calc_time
      redis.hget(experiment_config_key, :calc_time).to_i
    end

    def jstring(goal = nil)
      js_id = if goal.nil?
                name
              else
                name + "-" + goal
              end
      js_id.gsub('/', '--')
    end

    def cohorting_disabled?
      @cohorting_disabled ||= begin
        value = redis.hget(experiment_config_key, :cohorting)
        value.nil? ? false : value.downcase == "true"
      end
    end

    def disable_cohorting
      @cohorting_disabled = true
      redis.hset(experiment_config_key, :cohorting, "true")
    end

    def enable_cohorting
      @cohorting_disabled = false
      redis.hset(experiment_config_key, :cohorting, "false")
    end

    protected

    def experiment_config_key
      "experiment_configurations/#{@name}"
    end

    def load_metadata_from_configuration
      Split.configuration.experiment_for(@name)[:metadata]
    end

    def load_metadata_from_redis
      meta = redis.get(metadata_key)
      JSON.parse(meta) unless meta.nil?
    end

    def load_friendly_name_from_configuration
      Split.configuration.experiment_for(@name)[:friendly_name]
    end

    def load_friendly_name_from_redis
      redis.get(friendly_name_key)
    end

    def load_alternatives_from_configuration
      alts = Split.configuration.experiment_for(@name)[:alternatives]
      raise ArgumentError, "Experiment configuration is missing :alternatives array" unless alts
      if alts.is_a?(Hash)
        alts.keys
      else
        alts.flatten
      end
    end

    def load_alternatives_from_redis
      alternatives = case redis.type(@name)
                     when 'set' # convert legacy sets to lists
                       alts = redis.smembers(@name)
                       redis.del(@name)
                       alts.reverse.each {|a| redis.lpush(@name, a) }
                       redis.lrange(@name, 0, -1)
                     else
                       redis.lrange(@name, 0, -1)
                     end
      alternatives.map do |alt|
        alt = begin
                JSON.parse(alt)
              rescue
                alt
              end
        Split::Alternative.new(alt, @name)
      end
    end

    private

    def redis
      Split.redis
    end

    def redis_interface
      RedisInterface.new
    end

    def persist_experiment_configuration
      redis_interface.add_to_set(:experiments, name)
      redis_interface.persist_list(name, @alternatives.map { |alt| { alt.name => alt.weight }.to_json })
      goals_collection.save

      if @metadata
        redis.set(metadata_key, @metadata.to_json)
      else
        delete_metadata
      end
      redis.set(friendly_name_key, self.friendly_name)
    end

    def remove_experiment_configuration
      @alternatives.each(&:delete)
      goals_collection.delete
      delete_metadata
      redis.del(@name)
    end

    def experiment_configuration_has_changed?
      existing_alternatives = load_alternatives_from_redis
      existing_goals = Split::GoalsCollection.new(@name).load_from_redis
      existing_metadata = load_metadata_from_redis
      existing_alternatives.map(&:to_s) != @alternatives.map(&:to_s) ||
        existing_goals != @goals ||
        existing_metadata != @metadata
    end

    def goals_collection
      Split::GoalsCollection.new(@name, @goals)
    end

    def remove_experiment_cohorting
      @cohorting_disabled = false
      redis.hdel(experiment_config_key, :cohorting)
    end
  end
end
