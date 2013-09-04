class Player < ActiveRecord::Base
  belongs_to :sport
  belongs_to :team, :foreign_key => 'team'
  has_many :stat_events

  # Some positions are never used in NFL
  default_scope { where("position NOT IN('OLB', 'OL')") }

  has_and_belongs_to_many :rosters, join_table: 'rosters_players', association_foreign_key: "contest_roster_id"

  scope :autocomplete, ->(str)        { where("name ilike '%#{str}%'") }
  scope :on_team,      ->(team)       { where(team: team)}
  scope :in_market,    ->(market)     { where(team: market.games.map{|g| g.teams.map(&:abbrev)}.flatten) }
  scope :in_game,      ->(game)       { where(team: game.teams.pluck(:abbrev)) }
  scope :in_position,  ->(position)   { where(position: position) }
  scope :with_purchase_price,      -> { select('players.*, purchase_price') } # Must also join rosters_players
  scope :with_buy_price, -> { select('players.*, buy_prices.buy_price')} #Must join buy_prices
  scope :with_sell_price, -> { select('players.*, sell_prices.purchase_price, sell_prices.sell_price from players')} #join sell_prices

  def purchase_price
    self[:purchase_price]
  end
end
