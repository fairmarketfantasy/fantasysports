class Player < ActiveRecord::Base
  attr_protected
  belongs_to :sport
  #belongs_to :team, :foreign_key => 'team' # THe sportsdata data model is so bad taht sometimes this is an abbrev, sometimes its a stats id
  def team
    return self[:team] if self[:team].is_a? Team
    team = if self[:team].split('-').count > 2
      Team.where(:stats_id => self[:team])
    else
      Team.where(:abbrev => self[:team])
    end
    team.first
  end
  has_many :stat_events
  has_many :positions, :class_name => 'PlayerPosition'

  def purchase_price; self[:purchase_price]; end
  def buy_price; self[:buy_price]; end
  def sell_price; self[:sell_price]; end
  def score; self[:score]; end
  def locked; self[:locked]; end
  def market_id; self[:market_id]; end
  def is_eliminated; self[:is_eliminated]; end
  def position; self[:position]; end

  # Some positions are never used in NFL
  #default_scope { where("position NOT IN('OLB', 'OL')") }

  has_many :market_players
  has_many :rosters_players
  has_and_belongs_to_many :rosters, join_table: 'rosters_players'

  scope :autocomplete, ->(str)        { where("name ilike '%#{str}%'") }
  scope :on_team,      ->(team)       { where(team: team)}
  scope :in_market,    ->(market)     { where(team: market.games.map{|g| g.teams.map{|t| [t.abbrev, t.stats_id]} }.flatten) }
  scope :in_game,      ->(game)       { where(team: game.teams.map{|t| [t.abbrev, t.stats_id]}.flatten ) }
  scope :in_position,  ->(position)   { select('players.*, player_positions.position').joins('JOIN player_positions ON players.id=player_positions.player_id').where(["player_positions.position = ?", position]) }
  scope :normal_positions,      ->(sport_id) { select('players.*, player_positions.position'
                                    ).joins('JOIN player_positions ON players.id=player_positions.player_id'
                                    ).where("player_positions.position IN( '#{Positions.for_sport_id(sport_id).split(',').join("','") }')") }
  scope :order_by_ppg,          ->(dir = 'desc') { order("(total_points / (total_games + .001)) #{dir}") }
  scope :with_purchase_price,   -> { select('players.*, rosters_players.purchase_price') } # Must also join rosters_players
  scope :with_market,           ->(market) { select('players.*').select(
                                             "#{market.id} as market_id, mp.is_eliminated, mp.score, mp.locked"
                                           ).joins("JOIN market_players mp ON players.id=mp.player_id AND mp.market_id = #{market.id}") }
  scope :with_prices_for_players, -> (market, buy_in, player_ids) {
      select('players.*, mp.*').joins(
        "JOIN market_prices_for_players(#{market.id}, #{buy_in}, #{player_ids.push(-1).join(', ') }) mp ON mp.player_id=players.id")
  }

  # THIS IS REALLY SLOW, favor market_prices_for_players
  scope :with_prices,           -> (market, buy_in) {
      select('players.*, market_prices.*').joins("JOIN market_prices(#{market.id}, #{buy_in}) ON players.id = market_prices.player_id")
  }

  scope :benched,   -> { where(Player.bench_conditions ) }
  scope :active, -> () {
    where("status = 'ACT' AND NOT removed AND benched_games < 3")
  }

  scope :purchasable_for_roster, -> (roster) { 
    select(
      "players.*, player_positions.position, buy_prices.buy_price as buy_price, buy_prices.is_eliminated"
    ).joins("JOIN buy_prices(#{roster.id}) as buy_prices on buy_prices.player_id = players.id JOIN player_positions ON players.id=player_positions.player_id")
  }

  scope :with_sell_prices, -> (roster) { 
    select(
      "players.*, sell_prices.locked, sell_prices.score, sell_prices.purchase_price as purchase_price, sell_prices.sell_price as sell_price"
    ).joins( "JOIN sell_prices(#{roster.id}) as sell_prices on sell_prices.player_id = players.id" )
  }
  scope :sellable, -> { where('sell_prices.locked != true' ) }

  def self.bench_conditions
    "(players.status = 'IR' OR players.removed OR players.benched_games >= 3)"
  end

  def headshot_url(size = 65) # or 195
    return nil if position == 'DEF'
    return "https://fairmarketfantasy-prod.s3-us-west-2.amazonaws.com/headshots/#{stats_id}/#{size}.jpg"
  end

  def next_game_at # Requires with_market scope
    return nil unless self.market_id
    game = Market.find(self.market_id).games.order('game_time asc').select{|g| [g.home_team, g.away_team].include?(self.team)}.first
    return game && game.game_time - 5.minutes
  end

  def benched_games
    self.removed? ? 100 : super
  end

end
