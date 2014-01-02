class Player < ActiveRecord::Base
  attr_protected
  belongs_to :sport
  belongs_to :team, :foreign_key => 'team'
  has_many :stat_events

  def purchase_price; self[:purchase_price]; end
  def buy_price; self[:buy_price]; end
  def sell_price; self[:sell_price]; end
  def score; self[:score]; end
  def locked; self[:locked]; end
  def market_id; self[:market_id]; end
  def is_eliminated; self[:is_eliminated]; end

  # Some positions are never used in NFL
  default_scope { where("position NOT IN('OLB', 'OL')") }

  has_many :market_players
  has_many :rosters_players
  has_and_belongs_to_many :rosters, join_table: 'rosters_players'

  scope :autocomplete, ->(str)        { where("name ilike '%#{str}%'") }
  scope :on_team,      ->(team)       { where(team: team)}
  scope :in_market,    ->(market)     { where(team: market.games.map{|g| g.teams.map(&:abbrev)}.flatten) }
  scope :in_game,      ->(game)       { where(team: game.teams.pluck(:abbrev)) }
  scope :in_position,  ->(position)   { where(position: position) }
  scope :normal_positions,      -> { where(:position => %w(QB RB WR TE K DEF)) }
  scope :order_by_ppg,          ->(dir = 'desc') { order("(total_points / (total_games + .001)) #{dir}") }
  scope :with_purchase_price,   -> { select('players.*, rosters_players.purchase_price') } # Must also join rosters_players
  scope :with_market,           ->(market) { select('players.*').select(
                                             "#{market.id} as market_id, mp.is_eliminated, mp.score, mp.locked"
                                           ).joins('JOIN market_players mp ON players.stats_id=mp.player_stats_id') }
  scope :with_prices,           -> (market, buy_in) {
      select('players.*, market_prices.*').joins("JOIN market_prices(#{market.id}, #{buy_in}) ON players.id = market_prices.player_id")
  }

  scope :active, -> () {
    where("status = 'ACT' AND benched_games < 3")
  }

  scope :purchasable_for_roster, -> (roster) { 
    select(
      "players.*, buy_prices.buy_price as buy_price, buy_prices.is_eliminated"
    ).joins("JOIN buy_prices(#{roster.id}) as buy_prices on buy_prices.player_id = players.id")
  }

  scope :with_sell_prices, -> (roster) { 
    select(
      "players.*, sell_prices.locked, sell_prices.score, sell_prices.purchase_price as purchase_price, sell_prices.sell_price as sell_price"
    ).joins( "JOIN sell_prices(#{roster.id}) as sell_prices on sell_prices.player_id = players.id" )
  }
  scope :sellable, -> { where('sell_prices.locked != true' ) }

  def headshot_url(size = 65) # or 195
    return nil if position == 'DEF'
    return "https://fairmarketfantasy-prod.s3-us-west-2.amazonaws.com/headshots/#{stats_id}/#{size}.jpg"
  end

  def next_game_at # Requires with_market scope
    return nil unless self.market_id
    Market.find(self.market_id).games.select{|g| [g.home_team, g.away_team].include?(self.team)}.game_time - 5.minutes
  end

  def benched_games
    self.removed? ? 100 : super
  end

end
