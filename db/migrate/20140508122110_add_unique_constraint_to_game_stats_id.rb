class AddUniqueConstraintToGameStatsId < ActiveRecord::Migration
  def self.up
    change_column :games, :stats_id, :string

    ActiveRecord::Base.connection.execute('CREATE TABLE tmp as table games;')
    ActiveRecord::Base.connection.execute('DROP TABLE games;')
    ActiveRecord::Base.connection.execute('ALTER TABLE tmp RENAME TO games;')

    arr = Game.all.to_a.uniq.map(&:attributes)
    Game.destroy_all
    arr.each do |g|
      h = g
      h.delete 'id'
      h[:stats_id] = h['stats_id'].to_s
      Game.create! h
    end

    add_index :games, :stats_id, :unique => true
    add_index "games", ["bench_counted_at"], name: "index_games_on_bench_counted_at", using: :btree
    add_index "games", ["game_day"], name: "index_games_on_game_day", using: :btree
    add_index "games", ["game_time"], name: "index_games_on_game_time", using: :btree
  end

  def self.down
    remove_index :games, 'stats_id'
  end
end
