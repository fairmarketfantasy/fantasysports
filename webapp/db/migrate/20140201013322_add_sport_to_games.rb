class AddSportToGames < ActiveRecord::Migration
  def change
    add_column :games, :sport_id, :integer
  end
end
