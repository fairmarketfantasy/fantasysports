class AddIsGeneratedToGameRosters < ActiveRecord::Migration
  def change
    add_column :game_rosters, :is_generated, :boolean
  end
end
