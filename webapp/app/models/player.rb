class Player < ActiveRecord::Base
  belongs_to :sport
  belongs_to :team
  has_many :stat_events
  has_and_belongs_to_many :rosters, join_table: 'rosters_players', association_foreign_key: "contest_roster_id"

  scope :autocomplete, ->(str)        { where("name ilike '%#{str}%'") }
  scope :on_team,      ->(team_id)    { where(team_id: team_id)}
  scope :in_contest,   ->(contest_id) { joins(:rosters).where(rosters: {contest_id: contest_id}) }
  scope :in_game,      ->(game)       { Player.where(team_id: game.teams.pluck(:id)) }
end
