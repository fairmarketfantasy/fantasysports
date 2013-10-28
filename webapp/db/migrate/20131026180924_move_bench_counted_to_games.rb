class MoveBenchCountedToGames < ActiveRecord::Migration
  def change
    remove_column :market_players, :bench_counted, :boolean
    remove_column :market_players, :bench_counted_at, :timestamp
    add_column :games, :bench_counted, :boolean
    add_column :games, :bench_counted_at, :timestamp
    add_index :games, :bench_counted_at
  end
end
