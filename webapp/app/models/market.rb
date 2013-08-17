class Market < ActiveRecord::Base
  has_many :contests
  belongs_to :sport

  validates :shadow_bets, :shadow_bet_rate, presence: true

  scope :order_closed_asc,  ->       { order('closed_at asc') }
  scope :opened_after,      ->(time) { where("opened_at > ?", time) }
  scope :closed_after,      ->(time) { where('closed_at > ?', time) }

  paginates_per 25

end