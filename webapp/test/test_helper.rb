ENV["RAILS_ENV"] ||= "test"
require 'stripe_mock'
require File.expand_path('../../config/environment', __FILE__)
require File.expand_path('../../db/seeds', __FILE__)
require 'rails/test_help'
require 'minitest/spec'
require 'minitest/autorun'
require 'minitest/pride'
require 'debugger'

Market.load_sql_functions



class ActiveSupport::TestCase

  ActiveRecord::Migration.check_pending!
  include ActionDispatch::TestProcess

  setup { StripeMock.start }
  teardown { StripeMock.stop }

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

  def assert_email_sent(address = nil, &block)
    assert_difference('ActionMailer::Base.deliveries.size', &block)
    if address.present?
      assert_equal address, ActionMailer::Base.deliveries.last['to'].to_s
    end
  end

  def assert_email_not_sent(&block)
    assert_no_difference('ActionMailer::Base.deliveries.size', &block)
  end

  def resp_json
    resp = JSON.parse(response.body)
    if resp["data"]
      resp["data"] = JSONH.unpack(resp["data"])
    end
    resp
  end

  #creates one market with 2 games, 4 teams, and 36 players. market is not published.
  def setup_multi_day_market
    @teams = [create(:team1, :abbrev => "AA"),
              create(:team1, :abbrev => "BB"),
              create(:team1, :abbrev => "CC"),
              create(:team1, :abbrev => "DD")]
    @games = [create(:game, :home_team => @teams[0], :away_team => @teams[1], :game_time => Time.now.tomorrow + 10.minutes),
              create(:game, :home_team => @teams[2], :away_team => @teams[3], :game_time => Time.now.tomorrow  + 10.minutes, :game_day => Time.now.tomorrow.tomorrow.beginning_of_day)]
    @teams.each do |team|
      @players = Positions.default_NFL.split(',').map do |position|
        create :player, :team => team, :position => position
      end
    end
    @market = create :new_market
    @games.each do |game|
      GamesMarket.create(market_id: @market.id, game_stats_id: game.stats_id)
    end
  end

  #creates a published market with one game, two teams, and 18 players
  def setup_simple_market
    @team1 = create :team1
    @team2 = create :team2
    @game = create :game
    @players = []
    Positions.default_NFL.split(',').each do |position|
      player = create :player, :team => @team1, :position => position
      @players << player
      player = create :player, :team => @team2, :position => position
      @players << player
    end
    @market = create :new_market
    GamesMarket.create(market_id: @market.id, game_stats_id: @game.stats_id)
    @market.publish
    @market.add_default_contests
    @market.reload
  end

  #returns hash with routing and account_num
  def valid_account_token
    StripeMock.generate_card_token(
      :bank_account => {
        :country => "US",
        :routing_number => "110000000",
        :account_number => "000123456789",
      }
    )
  end

  def valid_card_token
    StripeMock.generate_card_token(last4: "4242", exp_year: 2017)
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
    confirmed_at { Time.now }
    password "123456"
    password_confirmation "123456"

    factory :paid_user do
      after(:create) do |user|
        user.customer_object = create(:customer_object, user: user)
        user.recipient       = create(:recipient, user: user)
        user.token_balance = 2000
        user.save!
      end
    end
  end

  factory :customer_object do
    balance 20000
    token { generate(:random_string) }
    after(:create) do |customer_object|
      create(:credit_card, token: StripeMock.generate_card_token(last4: "4242", exp_year: 2017), customer_object: customer_object)
    end
  end

  factory :credit_card do
    card_id { generate(:random_string) }
    card_number '4242424242424242'
  end

  factory :recipient do
    token { generate(:random_string) }
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

  factory :new_market, class: Market do
    shadow_bets 100000
    shadow_bet_rate 0.5
    published_at Time.now - 1.day
    opened_at Time.now + 1.minute
    closed_at Time.now + 2.minute
    total_bets 0
    sport_id 1
  end

  factory :roster do
    association :owner, factory: :paid_user
    association :market, factory: :open_market
    buy_in 1000
    remaining_salary 100000
    state 'in_progress'
    positions Positions.default_NFL
    association :contest_type
  end

  factory :contest do
    association :contest_type
    association :owner, factory: :user
    association :market, factory: :open_market
    invitation_code { generate(:random_string) }
    buy_in 1000

  end

  factory :contest_type do
    association :market, factory: :open_market
    name "some contest type"
    max_entries 100
    salary_cap 100000
    buy_in 1000
    rake 0.05
    payout_structure '[95000]'
    payout_description 'some payout description'
  end
end

# Yes, apparently this is supposed to be at the bottom.  I just work here.
require 'mocha/setup'
