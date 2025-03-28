# frozen_string_literal: true

require "spec_helper"
require "rack/test"
require "split/dashboard"

describe Split::Dashboard do
  include Rack::Test::Methods

  class TestDashboard < Split::Dashboard
    include Split::Helper

    get "/my_experiment" do
      ab_test(params[:experiment], "blue", "red")
    end
  end

  def app
    @app ||= TestDashboard
  end

  def link(color)
    Split::Alternative.new(color, experiment.name)
  end

  let(:experiment) {
    Split::ExperimentCatalog.find_or_create("link_color", "blue", "red")
  }

  let(:experiment_with_goals) {
    Split::ExperimentCatalog.find_or_create({ "link_color" => ["goal_1", "goal_2"] }, "blue", "red")
  }

  let(:metric) {
    Split::Metric.find_or_create(name: "testmetric", experiments: [experiment, experiment_with_goals])
  }

  let(:red_link) { link("red") }
  let(:blue_link) { link("blue") }

  before(:each) do
    Split.configuration.beta_probability_simulations = 1
  end

  it "should respond to /" do
    get "/"
    expect(last_response).to be_ok
  end

  context "start experiment manually" do
    before do
      Split.configuration.start_manually = true
    end

    context "experiment without goals" do
      it "should display a Start button" do
        experiment
        get "/"
        expect(last_response.body).to include("Start")

        post "/start?experiment=#{experiment.name}"
        get "/"
        expect(last_response.body).to include("Reset Data")
        expect(last_response.body).not_to include("Metrics:")
      end
    end

    context "experiment with metrics" do
      it "should display the names of associated metrics" do
        metric
        get "/"
        expect(last_response.body).to include("Metrics:testmetric")
      end
    end

    context "with goals" do
      it "should display a Start button" do
        experiment_with_goals
        get "/"
        expect(last_response.body).to include("Start")

        post "/start?experiment=#{experiment.name}"
        get "/"
        expect(last_response.body).to include("Reset Data")
      end
    end
  end

  describe "force alternative" do
    context "initial version" do
      let!(:user) do
        Split::User.new(@app, { experiment.name => "red" })
      end

      before do
        allow(Split::User).to receive(:new).and_return(user)
      end

      it "should set current user's alternative" do
        blue_link.participant_count = 7
        post "/force_alternative?experiment=#{experiment.name}", alternative: "blue"

        get "/my_experiment?experiment=#{experiment.name}"
        expect(last_response.body).to include("blue")
      end

      it "should not modify an existing user" do
        blue_link.participant_count = 7
        post "/force_alternative?experiment=#{experiment.name}", alternative: "blue"

        expect(user[experiment.key]).to eq("red")
        expect(blue_link.participant_count).to eq(7)
      end
    end

    context "incremented version" do
      let!(:user) do
        experiment.increment_version
        Split::User.new(@app, { "#{experiment.name}:#{experiment.version}" => "red" })
      end

      before do
        allow(Split::User).to receive(:new).and_return(user)
      end

      it "should set current user's alternative" do
        blue_link.participant_count = 7
        post "/force_alternative?experiment=#{experiment.name}", alternative: "blue"

        get "/my_experiment?experiment=#{experiment.name}"
        expect(last_response.body).to include("blue")
      end
    end
  end

  describe "index page" do
    context "with winner" do
      before { experiment.winner = "red" }

      it "displays `Reopen Experiment` button" do
        get "/"

        expect(last_response.body).to include("Reopen Experiment")
      end
    end

    context "without winner" do
      it "should not display `Reopen Experiment` button" do
        get "/"

        expect(last_response.body).to_not include("Reopen Experiment")
      end
    end
  end

  describe "reopen experiment" do
    before { experiment.winner = "red" }

    it "redirects" do
      post "/reopen?experiment=#{experiment.name}"

      expect(last_response).to be_redirect
    end

    it "removes winner" do
      post "/reopen?experiment=#{experiment.name}"

      expect(Split::ExperimentCatalog.find(experiment.name)).to_not have_winner
    end

    it "keeps existing stats" do
      red_link.participant_count = 5
      blue_link.participant_count = 7
      experiment.winner = "blue"

      post "/reopen?experiment=#{experiment.name}"

      expect(red_link.participant_count).to eq(5)
      expect(blue_link.participant_count).to eq(7)
    end
  end

  describe "update cohorting" do
    it "calls enable of cohorting when action is enable" do
      post "/update_cohorting?experiment=#{experiment.name}", { "cohorting_action": "enable" }

      expect(experiment.cohorting_disabled?).to eq false
    end

    it "calls disable of cohorting when action is disable" do
      post "/update_cohorting?experiment=#{experiment.name}", { "cohorting_action": "disable" }

      expect(experiment.cohorting_disabled?).to eq true
    end

    it "calls neither enable or disable cohorting when passed invalid action" do
      previous_value = experiment.cohorting_disabled?

      post "/update_cohorting?experiment=#{experiment.name}", { "cohorting_action": "other" }

      expect(experiment.cohorting_disabled?).to eq previous_value
    end
  end

  describe "initialize experiment" do
    before do
      Split.configuration.experiments = {
        my_experiment: {
          alternatives: [ "control", "alternative" ],
        }
      }
    end

    it "initializes the experiment when the experiment is given" do
      expect(Split::ExperimentCatalog.find("my_experiment")).to be nil

      post "/initialize_experiment", { experiment: "my_experiment" }

      experiment = Split::ExperimentCatalog.find("my_experiment")
      expect(experiment).to be_a(Split::Experiment)
    end

    it "does not attempt to initialize the experiment when empty experiment is given" do
      expect(Split::ExperimentCatalog).to_not receive(:find_or_create)
      post "/initialize_experiment", { experiment: "" }
    end

    it "does not attempt to initialize the experiment when no experiment is given" do
      expect(Split::ExperimentCatalog).to_not receive(:find_or_create)
      post "/initialize_experiment"
    end
  end

  it "should reset an experiment" do
    red_link.participant_count = 5
    blue_link.participant_count = 7
    experiment.winner = "blue"

    post "/reset?experiment=#{experiment.name}"

    expect(last_response).to be_redirect

    new_red_count = red_link.participant_count
    new_blue_count = blue_link.participant_count

    expect(new_blue_count).to eq(0)
    expect(new_red_count).to eq(0)
    expect(experiment.winner).to be_nil
  end

  it "should delete an experiment" do
    delete "/experiment?experiment=#{experiment.name}"
    expect(last_response).to be_redirect
    expect(Split::ExperimentCatalog.find(experiment.name)).to be_nil
  end

  it "should mark an alternative as the winner" do
    expect(experiment.winner).to be_nil
    post "/experiment?experiment=#{experiment.name}", alternative: "red"

    expect(last_response).to be_redirect
    expect(experiment.winner.name).to eq("red")
  end

  it "should display the start date" do
    experiment.start

    get "/"

    expect(last_response.body).to include("<small>#{experiment.start_time.strftime('%Y-%m-%d')}</small>")
  end

  it "should handle experiments without a start date" do
    Split.redis.hdel(:experiment_start_times, experiment.name)

    get "/"

    expect(last_response.body).to include("<small>Unknown</small>")
  end

  it "should be explode with experiments with invalid data" do
    red_link.participant_count = 1
    red_link.set_completed_count(10)

    blue_link.participant_count = 3
    blue_link.set_completed_count(2)

    get "/"

    expect(last_response).to be_ok
  end
end
