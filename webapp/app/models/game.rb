class Game < ActiveRecord::Base
  has_many :teams
  has_many :stat_events
end
