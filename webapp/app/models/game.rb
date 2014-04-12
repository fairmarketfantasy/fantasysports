class Game < ActiveRecord::Base
  attr_protected
  self.primary_key = "stats_id"
  has_many :games_markets, :inverse_of => :game, :foreign_key => "game_stats_id"
  has_many :markets, :through => :games_markets, :foreign_key => "game_stats_id"
  has_many :stat_events, :foreign_key => "game_stats_id", :inverse_of => :game
  belongs_to :sport

  validates :stats_id, :home_team, :away_team, :status, :game_day, :game_time, presence: true

  def teams
    # Again, because sportsdata uses both for different sports.  So dumb.
    Team.where("stats_id IN('#{self.home_team}', '#{self.away_team}') OR abbrev IN('#{self.home_team}', '#{self.away_team}')")
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

  def winning_team_status
    if winning_team == self.home_team
      get_home_team_status
    else
      get_away_team_status
    end
  end

  def losing_team_status
    if winning_team == self.home_team
      get_away_team_status
    else
      get_home_team_status
    end
  end

  def winning_team
    home = get_home_team_status
    away = get_away_team_status
    if home['points'] > away['points']
      home_team
    elsif away['points'] > home['points']
      away_team
    else
      nil
    end
  end

  def losing_team
    [self.home_team, self.away_team].find { |team| team != winning_team }
  end

  def unbench_players
    self.players.each { |p| p.update_attribute(:out, false) }
  end

  def calculate_ppg
    self.players.each { |p| p.calculate_ppg }
  end

  def create_market
    home_team = Team.find(self.home_team)
    away_team = Team.find(self.away_team)

    market = Market.new
    market.sport = self.sport
    market.name = away_team.name + ' @ ' + home_team.name
    market.shadow_bet_rate = 0.75
    market.shadow_bets = 0.0
    market.game_type = 'regular_season'
    market.opened_at = Time.now - 2.days
    market.started_at = self.game_time - 5.minutes
    market.closed_at = self.game_time - 5.minutes
    market.published_at = self.game_time - 2.days
    begin
      market.save!
    rescue ActiveRecord::RecordNotUnique
    end
    @market = Market.find_by_started_at_and_name(self.game_time - 5.minutes, away_team.name + ' @ ' + home_team.name)
    (home_team.players + away_team.players).each do |player|
      market_player = @market.market_players.new
      market_player.player = player
      market_player.shadow_bets = 0.0 # temp val
      market_player.bets = 0.0 # temp val
      market_player.player_stats_id = player.stats_id
      begin
        market_player.save!
      rescue ActiveRecord::RecordNotUnique
      end
    end
    begin
      self.markets << @market unless self.markets.any?
    rescue ActiveRecord::RecordNotUnique
    end
  end
end
