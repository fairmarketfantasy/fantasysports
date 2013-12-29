class Game < ActiveRecord::Base
  attr_protected
  self.primary_key = "stats_id" 
  has_many :games_markets, :inverse_of => :game, :foreign_key => "game_stats_id"
  has_many :markets, :through => :games_markets, :foreign_key => "game_stats_id"
  has_many :stat_events
  #belongs_to :home_team, :class_name => 'Team', :foreign_key => 'home_team'
  #belongs_to :away_team, :class_name => 'Team', :foreign_key => 'away_team'

  validates :stats_id, :home_team, :away_team, :status, :game_day, :game_time, presence: true

  def teams
    Team.where(abbrev: [self.home_team, self.away_team])
  end

  def players
    Player.where('team IN(?, ?)', self.home_team, self.away_team)
  end

  def market_players_for_market(market_id)
    MarketPlayer.select('players.*').joins('JOIN players p ON p.id=market_players.player_id').where('markets.id = ?', market_id).where('team IN(?, ?)', self.home_team, self.away_team)
  end

  def get_home_team_status
    JSON.parse(home_team_status || "{}")
  end

  def get_away_team_status
    JSON.parse(away_team_status || "{}")
  end

  def winning_team
    home = get_home_team_status
    away = get_away_team_status
    debugger if home['points'].nil?
    if home['points'] > away['points']
      home_team
    elsif away['points'] > home['points']
      away_team
    else
      nil
    end
  end

  def losing_team
    [self.home_team, self.away_team].find{|team| team != winning_team }
  end
end
