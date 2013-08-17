class GamesMarket < ActiveRecord::Base
  belongs_to :market
  belongs_to :game, :foreign_key => 'game_stats_id', :inverse_of => 'games_market'
  has_many :stat_events

  validates :stats_id, :home_team, :away_team, :status, :game_day, :game_time, presence: true

  def teams
    Team.where(name: [self.home_team, self.away_team])
  end
end

