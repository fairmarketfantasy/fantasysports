class Roster < ActiveRecord::Base
  has_and_belongs_to_many :players, join_table: 'rosters_players', foreign_key: "contest_roster_id"
  belongs_to :contest
  belongs_to :user
end
