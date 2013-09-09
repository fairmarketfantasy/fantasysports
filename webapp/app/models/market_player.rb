class MarketPlayer < ActiveRecord::Base
  belongs_to :market
  belongs_to :player

  def self.next_game_time_for_players(roster_players)
    game_time = self.where(:player_id => roster_players.map(&:player_id)).order('locked_at asc').detect{|p| p.locked_at > Time.now }
    game_time && game_time.locked_at
  end

  def self.players_live?(roster_players)
    self.where(:player_id => roster_players.map(&:player_id)).order('locked_at asc').any?{|p| p.locked_at > Time.now - 3.hours && p.locked_at < Time.now }
  end
end

