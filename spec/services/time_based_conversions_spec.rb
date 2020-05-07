# frozen_string_literal: true
require "spec_helper"

describe Split::Services::TimeBasedConversions do

  let(:user) { { "time_of_assignment_" + experiment_id => time_of_assignment } }
  let(:experiment_id) { "spec_experiment" }
  let(:time_now) do
    time_now = Time.now
    allow(Time).to receive(:now).and_return(time_now)
    time_now
  end

  describe ".within_conversion_time_frame?" do
    before do
      allow(Split.configuration).to receive(:experiments).and_return("spec_experiment" => { "window_of_time_for_conversion" => window_of_time })
    end

    context "when the experiment has no window of time defined" do
      let(:window_of_time) { nil }
      let(:time_of_assignment) { time_now - 120*60 }

      it "should return true" do
        expect(subject.within_conversion_time_frame?(user, experiment_id)).to eq(true)
      end
    end

    context "when the conversion is outside the time window" do
      let(:window_of_time) { 60 }
      let(:time_of_assignment) { time_now - 120*60 }

      it "should return false" do
        expect(subject.within_conversion_time_frame?(user, experiment_id)).to eq(false)
      end
    end

    context "when the conversion is within the time window" do
      let(:window_of_time) { 130 }
      let(:time_of_assignment) { time_now - 120*60 }

      it "should return true" do
        expect(subject.within_conversion_time_frame?(user, experiment_id)).to eq(true)
      end
    end
  end

  describe ".save_time_that_user_is_assigned" do
    let(:user) { { } }
    let(:time_of_assignment) { time_now }

    it "saves a Redis key that associates a user and experiment with the time they were assigned" do
      subject.save_time_that_user_is_assigned(user, experiment_id)
      puts user
      expect(user["time_of_assignment_" + experiment_id]).to eql time_of_assignment.to_s
    end
  end

end
