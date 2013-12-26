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
      GamesMarket.find_by_sql(["SELECT * FROM finish_game(?, ?, ?)", self.id, winner, loser])
    end
    reload
    self.finished_at = Time.new
    save!
  end
end

