class Market < ActiveRecord::Base

  validates :shadow_bets, :shadow_bet_rate, presence: true

  paginates_per 25

end