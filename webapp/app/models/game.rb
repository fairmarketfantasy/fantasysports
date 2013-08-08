class Game < ActiveRecord::Base
  belongs_to :home_team, class_name: "Team", foreign_key: "home_team_id"
  belongs_to :away_team, class_name: "Team", foreign_key: "away_team_id"
  has_many :stat_events

  validates :stats_id, :home_team_id, :away_team_id, :status, :game_day, :game_time, presence: true

  def teams
    Team.where(id: [self.home_team_id, self.away_team_id])
  end
end
