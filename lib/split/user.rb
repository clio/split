# frozen_string_literal: true
require 'forwardable'

module Split
  class User
    extend Forwardable
    def_delegators :@user, :keys, :[], :[]=, :delete
    attr_reader :user

    def initialize(context, adapter=nil)
      @user = adapter || Split::Persistence.adapter.new(context)
      @cleaned_up = false
    end

    def cleanup_old_experiments!
      return if @cleaned_up
      keys_without_finished_and_time_of_assignment(user.keys).each do |key|
        experiment = ExperimentCatalog.find key_without_version(key)
        if experiment.nil? || experiment.has_winner? || experiment.start_time.nil?
          user.delete key
          user.delete Experiment.finished_key(key)
          user.delete "#{key}:time_of_assignment"
        end
      end
      @cleaned_up = true
    end

    def max_experiments_reached?(experiment_key)
      if Split.configuration.allow_multiple_experiments == 'control'
        experiments = active_experiments
        experiment_key_without_version = key_without_version(experiment_key)
        count_control = experiments.count {|k,v| k == experiment_key_without_version || v == 'control'}
        experiments.size > count_control
      else
        !Split.configuration.allow_multiple_experiments &&
          keys_without_experiment(user.keys, experiment_key).length > 0
      end
    end

    def cleanup_old_versions!(experiment)
      keys = user.keys.select { |k| k.match(Regexp.new(experiment.name)) }
      keys_without_experiment(keys, experiment.key).each { |key| user.delete(key) }
    end

    def active_experiments
      experiment_pairs = {}
      keys_without_finished_and_time_of_assignment(user.keys).each do |key|
        Metric.possible_experiments(key_without_version(key)).each do |experiment|
          if !experiment.has_winner?
            experiment_pairs[key_without_version(key)] = user[key]
          end
        end
      end
      experiment_pairs
    end

    def alternative_key_for_experiment(experiment)
      if experiment.version > 0
        keys = user.keys

        #default to current experiment key when one isn't found
        user_experiment_key = experiment.key

        #first version is not colon delimited 
        if keys.include?(experiment.name)
          user_experiment_key = experiment.name
        else
          experiment.version.times do |version_number|
            key = "#{experiment.name}:#{version_number+1}"
            if keys.include?(key)
              user_experiment_key = key
              break
            end
          end
        end

        user_experiment_key
      else
        experiment.key
      end
    end

    private

    def keys_without_experiment(keys, experiment_key)
      keys.reject { |k| k.match(Regexp.new("^#{experiment_key}(:finished)?$")) || k.match("#{experiment_key}:time_of_assignment") }
    end

    def keys_without_finished_and_time_of_assignment(keys)
      keys.reject { |k| k.include?(":finished") || k.include?(":time_of_assignment") }
    end

    def key_without_version(key)
      key.split(/\:\d(?!\:)/)[0]
    end
  end
end
