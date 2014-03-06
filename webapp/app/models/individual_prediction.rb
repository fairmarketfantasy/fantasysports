class IndividualPrediction < ActiveRecord::Base
  belongs_to :roster
  belongs_to :player
  belongs_to :user
  has_many :event_predictions
  validates_presence_of :user_id, :player_id, :roster_id, :market_id, :pt
  attr_protected

  PT = BigDecimal.new(25)
end
