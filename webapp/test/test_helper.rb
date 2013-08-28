ENV["RAILS_ENV"] ||= "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/pride'
require 'debugger'

class ActiveSupport::TestCase

  ActiveRecord::Migration.check_pending!

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

  # Add more helper methods to be used by all tests here...
  class << self
    remove_method :describe
  end

  extend MiniTest::Spec::DSL

  register_spec_type self do |desc|
    desc < ActiveRecord::Base if desc.is_a? Class
  end


  include FactoryGirl::Syntax::Methods

  def setup_simple_market
    @market = create :open_market
    @team1 = create :team1
    @team2 = create :team2
    @game = create :game
    @players = Positions.default_NFL.split(',').map do |position|
      player = create :player, :team => [@team1, @team2].sample, :position => position
      @market.players << player
      player
    end
    @market.save!
  end
end


class ActionController::TestCase
  include Devise::TestHelpers

end


FactoryGirl.define do
  sequence :email do |n|
    "email#{n}@domain.com"
  end

  sequence(:random_string) {|n| (0...8).map{(65+rand(26)).chr}.join }

  factory :user do
    name "user footballfan"
    email { generate(:email) }
    password "123456"
    password_confirmation "123456"
  end

  factory :team1, class: Team do
    sport_id 1
    abbrev 'GB'
    name 'Packers'
    conference 'NFC'
    division 'NFC North'
    market 'Green Bay'
    state 'Wisconsin'
    country 'USA'
  end

  factory :team2, class: Team do
    sport_id 1
    abbrev 'SF'
    name '49ers'
    conference 'NFC'
    division 'NFC West'
    market 'San Francisco'
    state 'California'
    country 'USA'
  end

  factory :player do
    stats_id { generate(:random_string) }
    sport_id 1
    name "Spock"
  end

  factory :game do
    stats_id { generate(:random_string) }
    status 'created' # TODO: figure out what these are
    game_day Time.now.tomorrow.beginning_of_day
    game_time Time.now.tomorrow
    home_team 'GB'
    away_team 'SF'
  end

  factory :open_market, class: Market  do
    shadow_bets 1000
    shadow_bet_rate 0.75
    published_at Time.now - 4000
    opened_at Time.now - 1000
    closed_at nil
    state 'opened' # TODO: check this
    total_bets 5000
    sport_id 1
  end

  factory :roster do
    association :owner, factory: :user
    association :market, factory: :open_market
    buy_in 10
    remaining_salary 100000
    state 'in_progress'
    positions Positions.default_NFL
    contest_type "970"
  end

  #valid account creds
  factory :good_recipient, class: Recipient do
    stripe_id     { generate(:random_string) }
    account_num '000123456789'
    routing     '110000000'
  end
end

# Yes, apparently this is supposed to be at the bottom.  I just work here.
require 'mocha/setup'
