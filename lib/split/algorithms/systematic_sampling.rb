# frozen_string_literal: true
module Split
  module Algorithms
    module SystematicSampling
      def self.choose_alternative(experiment)
        count = experiment.next_cohorting_block_count

        block_length = experiment.cohorting_block_magnitude * experiment.alternatives.length
        block_num, index = count.divmod block_length

        block = generate_block(block_num, experiment)
        block[index]
      end

      private
       
      def self.generate_block(block_num, experiment)
        r = Random.new(block_num + experiment.cohorting_block_seed)
        block = (experiment.alternatives*experiment.cohorting_block_magnitude).shuffle(random: r)
      end
    end
  end
end
