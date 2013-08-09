class Game < ActiveRecord::Base
  has_many :stat_events

  validates :stats_id, :home_team_id, :away_team_id, :status, :game_day, :game_time, presence: true

  def teams
    Team.where(name: [self.home_team, self.away_team])
  end
end
