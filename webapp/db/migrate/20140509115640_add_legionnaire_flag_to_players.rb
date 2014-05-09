class AddLegionnaireFlagToPlayers < ActiveRecord::Migration
  def change
    add_column :players, :legionnaire, :boolean, :default => false, :null => false
  end
end
