# frozen_string_literal: true
require "spec_helper"

describe Split::Algorithms::SystematicSampling do
  let(:experiment) do
    Split::Experiment.new(
      'link_color',
      :alternatives => ['red', 'blue', 'green'],
      :algorithm => Split::Algorithms::SystematicSampling,
      :cohorting_block_magnitude => 2
    )
  end

  it "should return an alternative" do
    expect(Split::Algorithms::SystematicSampling.choose_alternative(experiment).class).to eq(Split::Alternative)
  end

  context "experiments with a random seed" do
    it "cohorts the first block of users equally into each alternative" do
      results = {'red' => 0, 'blue' => 0, 'green' => 0}
      6.times do
        results[Split::Algorithms::SystematicSampling.choose_alternative(experiment).name] += 1
      end

      expect(results).to eq({'red' => 2, 'blue' => 2, 'green' => 2})
    end

    it "cohorts the second block of users equally into each alternative" do
      6.times do
        Split::Algorithms::SystematicSampling.choose_alternative(experiment).name
      end

      results = {'red' => 0, 'blue' => 0, 'green' => 0}
      6.times do
        results[Split::Algorithms::SystematicSampling.choose_alternative(experiment).name] += 1
      end

      expect(results).to eq({'red' => 2, 'blue' => 2, 'green' => 2})
    end
  end

  context "experiments with set seed" do
    let(:seeded_experiment1) do
      Split::Experiment.new(
        'link_color',
        :alternatives => ['red', 'blue', 'green'],
        :algorithm => Split::Algorithms::SystematicSampling,
        :cohorting_block_seed => 1234
      )
    end

    let(:seeded_experiment2) do
      Split::Experiment.new(
        'link_highlight',
        :alternatives => ['red', 'blue', 'green'],
        :algorithm => Split::Algorithms::SystematicSampling,
        :cohorting_block_seed => 1234)
    end

    it "cohorts users in a set order" do
      results1 = []
      results2 = []

      12.times do
        results1 << Split::Algorithms::SystematicSampling.choose_alternative(seeded_experiment1).name
      end

      12.times do
        results2 << Split::Algorithms::SystematicSampling.choose_alternative(seeded_experiment2).name
      end

      expect(seeded_experiment1.cohorting_block_seed).to eq(seeded_experiment2.cohorting_block_seed)
      expect(results1).to eq(results2)
    end
  end
end
