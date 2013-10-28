class AddBenchedCountToPlayers < ActiveRecord::Migration
  def change
    add_column :players, :benched_games, :integer, :default => 0
    add_index :players, :benched_games
    add_column :market_players, :bench_counted, :boolean
    add_column :market_players, :bench_counted_at, :timestamp
    add_index :market_players, :bench_counted_at
  end
end
