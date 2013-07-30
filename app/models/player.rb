class Player < ActiveRecord::Base
  belongs_to :sport
  belongs_to :team
  has_many :stat_events
  has_and_belongs_to_many :contest_rosters
end
