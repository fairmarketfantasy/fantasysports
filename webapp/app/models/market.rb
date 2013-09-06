class Market < ActiveRecord::Base
  has_many :games_markets, :inverse_of => :market
  has_many :games, :through => :games_markets
  has_many :market_players
  has_many :players, :through => :market_players
  has_many :contests
  has_many :contest_types
  belongs_to :sport

  validates :shadow_bets, :shadow_bet_rate, :sport_id, presence: true

  scope :published_after,   ->(time) { where('published_at > ?', time)}
  scope :opened_after,      ->(time) { where("opened_at > ?", time) }
  scope :closed_after,      ->(time) { where('closed_at > ?', time) }

  paginates_per 25

  def accepting_rosters?
    ['published', 'opened'].include?(self.state)
  end

  #publish the market. returns the published market.
  def publish
    Market.find_by_sql("select * from publish_market(#{self.id})")[0]
  end

  def open
    Market.find_by_sql("select * from open_market(#{self.id})")[0]
  end

  def close
    Market.find_by_sql("select * from close_market(#{self.id})")[0]
  end

  #look for players in games that have started and remove them from the market
  #and update the price multiplier
  def lock_players
    Market.find_by_sql("SELECT * from lock_players(#{self.id})")[0]
  end

end
