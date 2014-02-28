class IndividualPrediction < ActiveRecord::Base
  belongs_to :roster_player
  validates_presence_of :roster_player_id, :event_type, :value, :less_or_more
  attr_protected
end
