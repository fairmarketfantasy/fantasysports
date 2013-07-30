class CreatePlayers < ActiveRecord::Migration
  def change
    create_table :players do |t|
      t.integer :sport_id
      t.integer :team_id
      t.decimal :point_per_game
      t.timestamps
    end
  end
end
