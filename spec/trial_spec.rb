# frozen_string_literal: true

require "spec_helper"
require "split/trial"

describe Split::Trial do
  let(:user) { mock_user }
  let(:alternatives) { ["basket", "cart"] }
  let(:experiment) do
    Split::Experiment.new("basket_text", alternatives: alternatives).save
  end

  it "should be initializeable" do
    experiment  = double("experiment")
    alternative = double("alternative", kind_of?: Split::Alternative)
    trial = Split::Trial.new(experiment: experiment, alternative: alternative)
    expect(trial.experiment).to eq(experiment)
    expect(trial.alternative).to eq(alternative)
  end

  describe "alternative" do
    it "should use the alternative if specified" do
      alternative = double("alternative", kind_of?: Split::Alternative)
      trial = Split::Trial.new(experiment: double("experiment"),
          alternative: alternative, user: user)
      expect(trial).not_to receive(:choose)
      expect(trial.alternative).to eq(alternative)
    end

    it "should load the alternative when the alternative name is set" do
      experiment = Split::Experiment.new("basket_text", alternatives: ["basket", "cart"])
      experiment.save

      trial = Split::Trial.new(experiment: experiment, alternative: "basket")
      expect(trial.alternative.name).to eq("basket")
    end
  end

  describe "metadata" do
    let(:metadata) { Hash[alternatives.map { |k| [k, "Metadata for #{k}"] }] }
    let(:experiment) do
      Split::Experiment.new("basket_text", alternatives: alternatives, metadata: metadata).save
    end

    it "has metadata on each trial" do
      trial = Split::Trial.new(experiment: experiment, user: user, metadata: metadata["cart"],
                               override: "cart")
      expect(trial.metadata).to eq(metadata["cart"])
    end

    it "has metadata on each trial from the experiment" do
      trial = Split::Trial.new(experiment: experiment, user: user)
      trial.choose!
      expect(trial.metadata).to eq(metadata[trial.alternative.name])
      expect(trial.metadata).to match(/#{trial.alternative.name}/)
    end
  end

  describe "#choose!" do
    let(:context) { double(on_trial_callback: "test callback") }
    let(:trial) do
      Split::Trial.new(user: user, experiment: experiment)
    end

    shared_examples_for "a trial with callbacks" do
      it "does not run if on_trial callback is not respondable" do
        Split.configuration.on_trial = :foo
        allow(context).to receive(:respond_to?).with(:foo, true).and_return false
        expect(context).to_not receive(:foo)
        trial.choose! context
      end
      it "runs on_trial callback" do
        Split.configuration.on_trial = :on_trial_callback
        expect(context).to receive(:on_trial_callback)
        trial.choose! context
      end
      it "does not run nil on_trial callback" do
        Split.configuration.on_trial = nil
        expect(context).not_to receive(:on_trial_callback)
        trial.choose! context
      end
    end

    def expect_alternative(trial, alternative_name)
      3.times do
        trial.choose! context
        expect(alternative_name).to include(trial.alternative.name)
      end
    end

    context "when override is present" do
      let(:override) { "cart" }
      let(:trial) do
        Split::Trial.new(user: user, experiment: experiment, override: override)
      end

      it_behaves_like "a trial with callbacks"

      it "picks the override" do
        expect(experiment).to_not receive(:next_alternative)
        expect_alternative(trial, override)
      end

      context "when alternative doesn't exist" do
        let(:override) { nil }
        it "falls back on next_alternative" do
          expect(experiment).to receive(:next_alternative).and_call_original
          expect_alternative(trial, alternatives)
        end
      end
    end

    context "when disabled option is true" do
      let(:trial) do
        Split::Trial.new(user: user, experiment: experiment, disabled: true)
      end

      it "picks the control", :aggregate_failures do
        Split.configuration.on_trial = :on_trial_callback
        expect(experiment).to_not receive(:next_alternative)

        expect(context).not_to receive(:on_trial_callback)

        expect_alternative(trial, "basket")
        Split.configuration.on_trial = nil
      end
    end

    context "when Split is globally disabled" do
      it "picks the control and does not run on_trial callbacks", :aggregate_failures do
        Split.configuration.enabled = false
        Split.configuration.on_trial = :on_trial_callback

        expect(experiment).to_not receive(:next_alternative)
        expect(context).not_to receive(:on_trial_callback)
        expect_alternative(trial, "basket")

        Split.configuration.enabled = true
        Split.configuration.on_trial = nil
      end
    end

    context "when experiment has winner" do
      let(:trial) do
        Split::Trial.new(user: user, experiment: experiment)
      end

      it_behaves_like "a trial with callbacks"

      it "picks the winner" do
        experiment.winner = "cart"
        expect(experiment).to_not receive(:next_alternative)

        expect_alternative(trial, "cart")
      end
    end

    context "when exclude is true" do
      let(:trial) do
        Split::Trial.new(user: user, experiment: experiment, exclude: true)
      end

      it_behaves_like "a trial with callbacks"

      it "picks the control" do
        expect(experiment).to_not receive(:next_alternative)
        expect_alternative(trial, "basket")
      end
    end

    context "when user is already participating" do
      it_behaves_like "a trial with callbacks"

      it "picks the same alternative" do
        user[experiment.key] = "basket"
        expect(experiment).to_not receive(:next_alternative)

        expect_alternative(trial, "basket")
      end

      context "when alternative is not found" do
        it "falls back on next_alternative" do
          user[experiment.key] = "notfound"
          expect(experiment).to receive(:next_alternative).and_call_original
          expect_alternative(trial, alternatives)
        end
      end

      context "when the user is in a previous version of the experiment" do
        context "and retain_user_alternatives_after_reset is true" do
          before do
            user[experiment.name] = "basket"

            experiment.retain_user_alternatives_after_reset = true
            experiment.increment_version
          end

          it "does not clean up previous version of the experiment" do
            expect(user[experiment.name]).to eq("basket")

            trial.choose!

            expect(user[experiment.name]).to eq("basket")
          end

          it "does not create new version of the experiment" do
            expect(user[experiment.key]).to be nil

            trial.choose!

            expect(user[experiment.key]).to be nil
          end

          it "does not increment the participant count" do
            original_count = experiment.participant_count

            trial.choose!

            expect(experiment.participant_count).to eql(original_count)
          end
        end

        context "and retain_user_alternatives_after_reset is false" do
          before do
            user[experiment.name] = "basket"

            experiment.retain_user_alternatives_after_reset = false
            experiment.increment_version
          end

          it "cleans up old version of the experiment" do
            expect(user[experiment.name]).to eq("basket")

            trial.choose!

            expect(user[experiment.name]).to be nil
          end

          it "creates new version of the experiment" do
            expect(user[experiment.key]).to be nil

            trial.choose!

            expect(["basket", "cart"]).to include(user[experiment.key])
          end

          it "increments the participant count" do
            original_count = experiment.participant_count

            trial.choose!

            expect(experiment.participant_count).to eql(original_count + 1)
          end
        end
      end

      context "when the user is in current version of the experiment" do
        context "and retain_user_alternatives_after_reset is true" do
          before do
            user[experiment.name] = "basket"

            experiment.retain_user_alternatives_after_reset = true
          end

          it "does not increment the participant count" do
            original_count = experiment.participant_count

            trial.choose!

            expect(experiment.participant_count).to eql(original_count)
          end

          it "does not clean up previous version of the experiment" do
            expect(user[experiment.key]).to eq("basket")

            trial.choose!

            expect(user[experiment.key]).to eq("basket")
          end
        end

        context "and retain_user_alternatives_after_reset is false" do
          before do
            user[experiment.name] = "basket"

            experiment.retain_user_alternatives_after_reset = false
          end

          it "does not increment the participant count" do
            original_count = experiment.participant_count

            trial.choose!

            expect(experiment.participant_count).to eql(original_count)
          end

          it "does not clean up previous version of the experiment" do
            expect(user[experiment.key]).to eq("basket")

            trial.choose!

            expect(user[experiment.key]).to eq("basket")
          end
        end
      end
    end

    context "when user is a new participant" do
      it "picks a new alternative and runs on_trial_choose callback", :aggregate_failures do
        Split.configuration.on_trial_choose = :on_trial_choose_callback

        expect(experiment).to receive(:next_alternative).and_call_original
        expect(context).to receive(:on_trial_choose_callback)

        trial.choose! context

        expect(trial.alternative.name).to_not be_empty
        Split.configuration.on_trial_choose = nil
      end

      it "assigns user to an alternative" do
        trial.choose! context

        expect(alternatives).to include(user[experiment.name])
      end

      context "when cohorting is disabled" do
        before(:each) { allow(experiment).to receive(:cohorting_disabled?).and_return(true) }

        it "picks the control and does not run on_trial callbacks" do
          Split.configuration.on_trial = :on_trial_callback

          expect(experiment).to_not receive(:next_alternative)
          expect(context).not_to receive(:on_trial_callback)
          expect_alternative(trial, "basket")

          Split.configuration.enabled = true
          Split.configuration.on_trial = nil
        end

        it "user is not assigned an alternative" do
          trial.choose! context

          expect(user[experiment]).to eq(nil)
        end
      end
    end
  end

  describe "#complete!" do
    let(:trial) { Split::Trial.new(user: user, experiment: experiment) }

    before do
      allow(Split.configuration).to receive(:experiments).and_return(experiment.name => { "window_of_time_for_conversion_in_minutes" => 60 })

      trial.choose!
    end

    it "removes the context keys for that experiment" do
      user[experiment.key + ":external_key"] = "value"
      trial.complete!
      expect(user.keys).to eq [experiment.key]
    end

    context "and the user is not within the conversion time frame" do
      it "does not convert" do
        old_completed_count = trial.alternative.completed_count

        allow(Time).to receive(:now).and_return(Time.now + 60*120)

        trial.complete!
        expect(trial.alternative.completed_count).to be(old_completed_count)
      end
    end

    context "and the user is within the conversion time frame" do
      it "does convert" do
        old_completed_count = trial.alternative.completed_count

        trial.complete!
        expect(trial.alternative.completed_count).to be(old_completed_count+1)
      end
    end

    context "when there are no goals" do
      let(:trial) { Split::Trial.new(user: user, experiment: experiment) }

      it "should complete the trial" do
        trial.choose!
        old_completed_count = trial.alternative.completed_count
        trial.complete!
        expect(trial.alternative.completed_count).to eq(old_completed_count + 1)
      end
    end

    context "when there are many goals" do
      let(:goals) { [ "goal1", "goal2" ] }
      let(:trial) { Split::Trial.new(user: user, experiment: experiment, goals: goals) }

      it "increments the completed count corresponding to the goals" do
        trial.choose!
        old_completed_counts = goals.map { |goal| [goal, trial.alternative.completed_count(goal)] }.to_h
        trial.complete!
        goals.each { | goal | expect(trial.alternative.completed_count(goal)).to eq(old_completed_counts[goal] + 1) }
      end
    end

    context "when there is 1 goal of type string" do
      let(:goal) { "goal" }
      let(:trial) { Split::Trial.new(user: user, experiment: experiment, goals: goal) }

      it "increments the completed count corresponding to the goal" do
        trial.choose!
        old_completed_count = trial.alternative.completed_count(goal)
        trial.complete!
        expect(trial.alternative.completed_count(goal)).to eq(old_completed_count + 1)
      end
    end
  end

  describe "#within_conversion_time_frame?" do
    let(:trial) { Split::Trial.new(:user => user, :experiment => experiment) }

    it "memoizes the result" do
      allow(Split.configuration).to receive(:experiments).and_return(experiment.name => { "window_of_time_for_conversion_in_minutes" => 60 })
      trial.choose!

      expect(Time).to receive(:parse).once.and_call_original

      trial.within_conversion_time_frame?
      trial.within_conversion_time_frame?
    end

    context "when window of time for conversion in minutes is configured" do
      before do
        allow(Split.configuration).to receive(:experiments).and_return(experiment.name => { "window_of_time_for_conversion_in_minutes" => 60 })
        trial.choose!
      end

      it "returns false when user time of assignment is nil" do
        user["#{experiment.key}:time_of_assignment"] = nil

        expect(trial.within_conversion_time_frame?).to be_falsey
      end

      it "returns false when user time of assignment is empty" do
        user["#{experiment.key}:time_of_assignment"] = ""

        expect(trial.within_conversion_time_frame?).to be_falsey
      end

      it "returns false when user is not within the conversion time frame" do
        allow(Time).to receive(:now).and_return(Time.now + 60*120)

        expect(trial.within_conversion_time_frame?).to be_falsey
      end

      it "returns true when user is within the conversion time frame" do
        expect(trial.within_conversion_time_frame?).to be_truthy
      end
    end

    context "when window of time for conversion in minutes is not configured" do
      before do
        trial.choose!
      end

      it "returns true" do
        expect(trial.within_conversion_time_frame?).to be_truthy
      end
    end
  end

  describe "alternative recording" do
    before(:each) { Split.configuration.store_override = false }

    context "when override is present" do
      it "stores when store_override is true" do
        trial = Split::Trial.new(user: user, experiment: experiment, override: "basket")

        Split.configuration.store_override = true
        expect(user).to receive("[]=")
        trial.choose!
        expect(trial.alternative.participant_count).to eq(1)
      end

      it "does not store when store_override is false" do
        trial = Split::Trial.new(user: user, experiment: experiment, override: "basket")

        expect(user).to_not receive("[]=")
        trial.choose!
      end
    end

    context "when disabled is present" do
      it "stores when store_override is true" do
        trial = Split::Trial.new(user: user, experiment: experiment, disabled: true)

        Split.configuration.store_override = true
        expect(user).to receive("[]=")
        trial.choose!
      end

      it "does not store when store_override is false" do
        trial = Split::Trial.new(user: user, experiment: experiment, disabled: true)

        expect(user).to_not receive("[]=")
        trial.choose!
      end
    end

    context "when exclude is present" do
      it "does not store" do
        trial = Split::Trial.new(user: user, experiment: experiment, exclude: true)

        expect(user).to_not receive("[]=")
        trial.choose!
      end
    end

    context "when experiment has winner" do
      let(:trial) do
        experiment.winner = "cart"
        Split::Trial.new(user: user, experiment: experiment)
      end

      it "does not store" do
        expect(user).to_not receive("[]=")
        trial.choose!
      end
    end
  end
end
