class CreatePlayers < ActiveRecord::Migration
  def change
    create_table :players do |t|
      t.string :stats_id
      t.integer :sport_id
      t.integer :team_id
      t.string :name
      t.string :name_abbr
      t.string :birthdate
      t.integer :height
      t.integer :weight
      t.string :college
      t.string :position
      t.integer :jersey_number
      t.string :status
      t.string :salary
      t.integer :total_games, :null => false, :default => 0
      t.integer :total_points, :null => false, :default => 0
      t.decimal :points_per_game
      t.timestamps
    end

    add_index :players, :stats_id
    add_index :players, :team_id
    add_index :players, :points_per_game
  end
end
