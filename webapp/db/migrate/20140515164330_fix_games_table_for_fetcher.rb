class FixGamesTableForFetcher < ActiveRecord::Migration
  def change
    change_column :games, :stats_id, :string, :null => false
  end
end
