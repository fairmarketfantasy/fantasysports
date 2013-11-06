class LeagueContest < ActiveRecord::Base
  attr_protected
  belongs_to :contest
  belongs_to :league
end


