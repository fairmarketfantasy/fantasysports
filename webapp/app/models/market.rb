class Market < ActiveRecord::Base
  has_many :games_markets
  has_many :games, :through => :games_markets
  has_many :market_players
  has_many :players, :through => :market_players
  has_many :contests
  belongs_to :sport

  validates :shadow_bets, :shadow_bet_rate, presence: true

  scope :opened_after,      ->(time) { where("opened_at > ?", time) }
  scope :closed_after,      ->(time) { where('closed_at > ?', time) }

  paginates_per 25

end
