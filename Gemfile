# frozen_string_literal: true

source "https://rubygems.org"

ruby file: ".ruby-version"

gemspec

gem "rubocop", require: false
gem "codeclimate-test-reporter"
gem "concurrent-ruby", "< 1.3.5"

gem "rails", "~> #{ENV.fetch('RAILS_VERSION', '8.0')}"
