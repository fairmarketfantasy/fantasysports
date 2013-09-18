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

  # Some positions are never used in NFL
  default_scope { where("position NOT IN('OLB', 'OL')") }

  has_and_belongs_to_many :rosters, join_table: 'rosters_players', association_foreign_key: "contest_roster_id"

  scope :autocomplete, ->(str)        { where("name ilike '%#{str}%'") }
  scope :on_team,      ->(team)       { where(team: team)}
  scope :in_market,    ->(market)     { where(team: market.games.map{|g| g.teams.map(&:abbrev)}.flatten) }
  scope :in_game,      ->(game)       { where(team: game.teams.pluck(:abbrev)) }
  scope :in_position,  ->(position)   { where(position: position) }
  scope :normal_positions,      -> { where(:position => %w(QB RB WR TE K DEF)) }
  scope :with_purchase_price,   -> { select('players.*, rosters_players.purchase_price') } # Must also join rosters_players

  scope :purchasable_for_roster, -> (roster) { 
    select(
      "players.*, buy_prices.buy_price as buy_price"
    ).joins("JOIN buy_prices(#{roster.id}) as buy_prices on buy_prices.player_id = players.id")
  }

  scope :with_sell_prices, -> (roster) { 
    select(
      "players.*, sell_prices.locked, sell_prices.score, sell_prices.purchase_price as purchase_price, sell_prices.sell_price as sell_price"
    ).joins( "JOIN sell_prices(#{roster.id}) as sell_prices on sell_prices.player_id = players.id" )
  }
  scope :sellable, -> { where('sell_prices.locked != true' ) }

end
