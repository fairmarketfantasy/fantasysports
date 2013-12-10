class GamesMarket < ActiveRecord::Base
  attr_accessible :game_stats_id, :market_id
  belongs_to :market, :inverse_of => :games_markets
  belongs_to :game, :foreign_key => 'game_stats_id', :inverse_of => :games_markets

  def finish!
    case self.market.game_type
    when 'regular_season' then

    when 'single_elimination' then

    end
  end
end

