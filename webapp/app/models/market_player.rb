class MarketPlayer < ActiveRecord::Base
  attr_protected
  belongs_to :market
  belongs_to :player

  def self.next_game_time_for_roster_players(roster)
    game_time = self.where(:market_id => roster.market_id, :player_id => roster.players.map(&:id)).order('locked_at asc').detect{|p| p.locked_at && p.locked_at > Time.now }
    game_time && game_time.locked_at
  end

  def self.players_live?(market_id, roster_players)
    self.where(:player_id => roster_players.map(&:player_id), :market_id => market_id).order('locked_at asc').any?{|p| p.locked_at && p.locked_at > Time.now - 3.5.hours && p.locked_at < Time.now }
  end

  def price_in_10_dollar_contest
    MarketPlayer.find_by_sql(["select price(?, ?, ?, ?) as price", self.bets, self.market.total_bets, 1000, self.market.price_multiplier])[0][:price].to_i
  end
end

