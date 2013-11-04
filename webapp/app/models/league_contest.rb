class LeagueContest < ActiveRecord::Base
  belongs_to :contest
  belongs_to :league
end


