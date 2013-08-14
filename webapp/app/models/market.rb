class Market < ActiveRecord::Base
  has_many :contests
  belongs_to :sport

  validates :shadow_bets, :shadow_bet_rate, presence: true

  paginates_per 25

end