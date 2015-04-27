class EventPrediction < ActiveRecord::Base
  belongs_to :individual_prediction
  attr_protected
  validates_presence_of :event_type, :value, :diff
end
