class Game < ActiveRecord::Base
  self.primary_key = "stats_id" 
  has_one :games_market, :inverse_of => :game, :foreign_key => "game_stats_id"
  has_one :market, :through => :games_markets
  has_many :stat_events

  validates :stats_id, :home_team, :away_team, :status, :game_day, :game_time, presence: true

  def teams
    Team.where(abbrev: [self.home_team, self.away_team])
  end
end
