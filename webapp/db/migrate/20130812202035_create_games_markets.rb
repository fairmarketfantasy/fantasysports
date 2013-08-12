class CreateGamesMarkets < ActiveRecord::Migration
  def change
    remove_column :stat_events, :point_type, :integer
    remove_column :stat_events, :game_event_stats_id, :string
    create_table :games_markets do |t|
      t.integer :game_stats_id
      t.integer :market_id
    end
  end
end
