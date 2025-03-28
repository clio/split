# frozen_string_literal: true

# A multi-armed bandit implementation inspired by
# @aaronsw and victorykit/whiplash

module Split
  module Algorithms
    module Whiplash
      class << self
        def choose_alternative(experiment)
          experiment[best_guess(experiment.alternatives)]
        end

        private

        def arm_guess(participants, completions)
          a = [participants, 0].max
          b = [participants-completions, 0].max
          Split::Algorithms.beta_distribution_rng(a + fairness_constant, b + fairness_constant)
        end

        def best_guess(alternatives)
          guesses = {}
          alternatives.each do |alternative|
            guesses[alternative.name] = arm_guess(alternative.participant_count, alternative.all_completed_count)
          end
          gmax = guesses.values.max
          best = guesses.keys.select { |name| guesses[name] ==  gmax }
          best.sample
        end

        def fairness_constant
          7
        end
      end
    end
  end
end
