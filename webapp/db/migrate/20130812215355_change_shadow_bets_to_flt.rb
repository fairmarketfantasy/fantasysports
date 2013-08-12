class ChangeShadowBetsToFlt < ActiveRecord::Migration
  def change
    change_column :markets, :shadow_bets, :decimal
  end
end
