# Table for saving PT for 'win the cup' and 'win groups' separately
class PredictionPt < ActiveRecord::Base
  attr_accessible :stats_id, :pt, :competition_type
  validates_presence_of :stats_id #stats_id for team
end
