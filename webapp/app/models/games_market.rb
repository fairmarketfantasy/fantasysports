class GamesMarket < ActiveRecord::Base
  attr_protected
  belongs_to :market, :inverse_of => :games_markets
  belongs_to :game, :foreign_key => 'game_stats_id', :inverse_of => :games_markets

  def finish!
    winner = game.winning_team
    loser = game.losing_team
    case self.market.game_type
    when 'regular_season' then
      nil # do nothing
    when 'single_elimination' then
      GamesMarket.find_by_sql(["SELECT * FROM finish_elimination_game(?, ?, ?)", self.id, winner, loser])
    when 'team_single_elimination' then
      home = game.get_home_team_status
      away = game.get_away_team_status
      winning_mp = market.market_players.where(:player_stats_id => Team.where(:abbrev => game.winning_team).first.players.map(&:stats_id)).first
      losing_mp = market.market_players.where(:player_stats_id => Team.where(:abbrev => game.losing_team).first.players.map(&:stats_id)).first
      StatEvent.create!(:player_stats_id => winning_mp.player_stats_id, :game_stats_id => game.stats_id, :activity => "Win vs #{game.losing_team}", :point_value => 100, :data => '{}')
      StatEvent.create!(:player_stats_id => winning_mp.player_stats_id, :game_stats_id => game.stats_id, :activity => "Points Scored vs #{game.losing_team}", :point_value => 2 * home['points'], :data => '{}')
      StatEvent.create!(:player_stats_id => winning_mp.player_stats_id, :game_stats_id => game.stats_id, :activity => "Points Against vs #{game.losing_team}", :point_value => -2 * away['points'], :data => '{}')

      StatEvent.create!(:player_stats_id => losing_mp.player_stats_id, :game_stats_id => game.stats_id, :activity => "Points Scored vs #{game.winning_team}", :point_value => 2 * away['points'], :data => '{}')
      StatEvent.create!(:player_stats_id => losing_mp.player_stats_id, :game_stats_id => game.stats_id, :activity => "Points Against vs #{game.winning_team}", :point_value => -2 * home['points'], :data => '{}')
      # TODO: Whatever market transformations are needed
      # Mark losing player as eliminated
    end
    reload
    game.update_attribute(:status, 'closed') unless game.status == 'closed' # Just in case it doesn't get closed by the datafetcher, which happens sometimes
    self.finished_at = Time.new
    save!
  end
end

