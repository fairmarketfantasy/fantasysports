class DefaultGameRosterScoreZero < ActiveRecord::Migration
  def self.up
    change_column :game_rosters, :score, :decimal, :null => false, :default => 0
  end

  def self.down
    change_column :game_rosters, :score, :integer
  end
end
