class InitialShadowBets < ActiveRecord::Migration
  def change
    add_column :markets, :initial_shadow_bets, :decimal, :null => true
    add_column :market_players, :initial_shadow_bets, :decimal, :null => true
  end
end
