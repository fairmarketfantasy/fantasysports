class FixDataFetcher < ActiveRecord::Migration
  def change
    remove_column :games, :id
    add_column :games, :id, :primary_key
    remove_index :games, :stats_id
    add_index :games, :stats_id
  end
end
