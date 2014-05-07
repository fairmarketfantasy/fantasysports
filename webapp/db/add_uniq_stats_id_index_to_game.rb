# better use later, when sure that it won`t brake logic.
# TODO: remove dups from `games`
class AddUniqStatsIdIndexToGame < ActiveRecord::Migration
  def self.up
    ActiveRecord::Base.connection.execute('CREATE TABLE tmp as SELECT DISTINCT (stats_id) FROM games;
                        DROP TABLE games;
                        ALTER TABLE tmp RENAME TO games;')

    add_index :games, :stats_id, :unique => true
  end

  def self.down
    remove_index :games, 'stats_id'
  end
end
