# frozen_string_literal: true
module Split
  module Algorithms
    module SystematicSampling
      def self.choose_alternative(experiment)
        count = experiment.next_cohorting_block_index

        block_length = experiment.cohorting_block_magnitude * experiment.alternatives.length
        block_num, index = count.divmod block_length

        r = Random.new(block_num + experiment.cohorting_block_seed)
        block = (experiment.alternatives*experiment.cohorting_block_magnitude).shuffle(random: r)
        block[index]
      end
    end
  end
end
