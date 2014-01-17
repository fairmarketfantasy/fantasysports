ENV["RAILS_ENV"] ||= "test"
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

  setup {  }
  teardown { }

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

  def create_team1
    @team1 ||= create(:team1)
  end
  def create_team2
    @team2 ||= create(:team2)
  end

  def setup_team(opts = {})
    team = create(:team, opts)
    players = Positions.default_NFL.split(',').map{|p| create(:player, :team => team, :position => p) }
    team
  end

  def add_bets_to_market(market)
    market.publish
    total_bets = 0
    market.market_players.each do |mp|
        bets = 100 * 100 * rand(1..10)
        mp.initial_shadow_bets = mp.shadow_bets = mp.bets = bets
        mp.save!
        total_bets += bets
    end 
    market.total_bets = market.shadow_bets = market.initial_shadow_bets = total_bets
    market.save!
  end

  def play_game(game)
    # Home team always wins!
    [game.away_team, game.home_team].each_with_index do |team, i|
      team = Team.find(team) if team.is_a?(String)
      team.players.each do |p|
        StatEvent.create!(
          :game_stats_id => game.stats_id,
          :player_stats_id => p.stats_id,
          :point_value => i+1,
          :activity => 'rushing',
          :data => ''
        )
      end
    end
    game.update_attributes(:home_team_status => '{"points": 14}', :away_team_status => '{"points": 7}', :status => 'closed', :game_time => Time.new-1.minute)
    game
  end
  
  def setup_single_elimination_market
    teams = (1..4).map{ setup_team }
    @game1_1 = create(:game, :home_team => teams[0], :away_team => teams[1], :game_time => Time.now + 10.minute) # Publish subtracts 5 minutes
    @game1_2 = create(:game, :home_team => teams[2], :away_team => teams[3], :game_time => Time.now + 10.minute)
    @market, @team_market = Market.create_single_elimination_game(1, "player market", "team market", 2600, 1300)
    @market.add_single_elimination_game(@game1_1)
    @market.add_single_elimination_game(@game1_2)
    [@market, @team_market].each{|m| m.update_attribute(:published_at, Time.new - 1.minute) }
    add_bets_to_market(@market)
    add_bets_to_market(@team_market)
    @market.reload
  end

  #creates one market with 2 games, 4 teams, and 36 players. market is not published.
  def setup_multi_day_market
    @teams = (0..3).map{ create(:team) }
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
    add_bets_to_market(@market)
    @market
  end

  def setup_multi_day_market2
    @games = [create(:game, :home_team => @teams[0], :away_team => @teams[1], :game_time => Time.now.tomorrow + 10.minutes),
              create(:game, :home_team => @teams[2], :away_team => @teams[3], :game_time => Time.now.tomorrow  + 10.minutes, :game_day => Time.now.tomorrow.tomorrow.beginning_of_day)]
    @market = create :new_market
    @games.each do |game|
      GamesMarket.create(market_id: @market.id, game_stats_id: game.stats_id)
    end
    @market.publish
  end

  #creates a published market with one game, two teams, and 18 players
  def setup_simple_market
    @team1 = create_team1
    @team2 = create_team2
    @game = create :game
    @players = []
    other_players = []
    Positions.default_NFL.split(',').each do |position|
      player = create :player, :team => @team1, :position => position
      @players << player
      player = create :player, :team => @team2, :position => position
      other_players << player
    end
    @players = @players.concat(other_players)
    @market = create :new_market
    GamesMarket.create(market_id: @market.id, game_stats_id: @game.stats_id)
    @market.add_default_contests
    add_bets_to_market(@market)
    @market.reload
  end

  def add_lollapalooza(market)
    ContestType.create!(
      market_id: market.id,
      name: '0.13k',
      description: '$130',
      max_entries: 13,
      buy_in: 1000,
      rake: 3000,
      payout_structure: '[5000, 2500, 2500]',
      salary_cap: 100000,
      payout_description: '[5000, 2500, 2500]',
      takes_tokens: false,
      positions:Positions.default_NFL,
      limit: 1
    )
    market.contest_types.reload
    market
  end

  def initialize_player_bets(market)
    bets = market.market_players.count * 1000
    market.market_players.update_all(:shadow_bets => 1000, :bets => 1000, :initial_shadow_bets => 1000)
    market.update_attributes(:total_bets => bets, :shadow_bets => bets, :initial_shadow_bets => bets)
    bets
  end
  #returns hash with routing and account_num
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
        user.confirm!
        user.customer_object.update_attributes(is_active: true, has_agreed_terms: true)
        user.recipient       = create(:recipient, user: user, paypal_email: user.email, paypal_email_confirmation: user.email)
        user.token_balance = 2000
        user.save!
      end
    end
  end

  factory :customer_object do
    balance 20000
    token { generate(:random_string) }
    after(:create) do |customer_object|
      c = create(:credit_card, customer_object: customer_object)
      customer_object.default_card = c
      customer_object.has_agreed_terms = true
      customer_object.is_active = true
      customer_object.save!
    end
  end

  factory :credit_card do
    paypal_card_id { generate(:random_string) }
    card_number '4242424242424242'
    expires Time.new(2019, 12)
  end

  factory :recipient do
    paypal_email { generate(:email) }
  end

  factory :league do
    name "blah"
  end

  factory :team, class: Team do
    sport_id 1
    abbrev { generate(:random_string)[0..5] }
    name  { generate(:random_string) }
    conference 'NFC'
    division 'NFC North'
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
    status "ACT"
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
    game_type 'regular_season'
  end

  factory :new_market, class: Market do
    game_type "regular_season"
    shadow_bets 100000
    shadow_bet_rate 0.5
    published_at Time.now - 1.day
    started_at Time.now - 10.minute
    opened_at Time.now + 5.minute
    closed_at Time.now + 10.minute
    fill_roster_times "[[" + (Time.new + 5.minute).to_i.to_s + ", 0.5]]"
    total_bets 0
    sport_id 1
  end

  factory :roster do
    association :owner, factory: :paid_user
    association :market, factory: :open_market
    buy_in 1000
    remaining_salary 100000
    state 'in_progress'
    association :contest_type
    after(:create) do |roster|
      roster.buy_in = roster.contest_type.buy_in
      roster.takes_tokens = roster.contest_type.takes_tokens
      roster.save!
    end
  end

  factory :contest do
    association :contest_type
    association :owner, factory: :user
    association :market, factory: :open_market
    invitation_code { generate(:random_string) }
    buy_in 1000
    num_rosters 0
    user_cap 10
  end

  factory :contest_type do
    association :market, factory: :open_market
    name "some contest type"
    max_entries 100
    salary_cap 100000
    buy_in 1000
    rake 5000
    payout_structure '[95000]'
    payout_description 'some payout description'
    positions Positions.default_NFL
  end
end

# Yes, apparently this is supposed to be at the bottom.  I just work here.
require 'mocha/setup'
