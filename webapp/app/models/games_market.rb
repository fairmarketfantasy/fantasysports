class GamesMarket < ActiveRecord::Base
  belongs_to :market, :inverse_of => :games_markets
  belongs_to :game, :foreign_key => 'game_stats_id', :inverse_of => :games_markets

end

