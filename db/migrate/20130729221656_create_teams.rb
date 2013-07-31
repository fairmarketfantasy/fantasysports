class CreateTeams < ActiveRecord::Migration
  def change
    create_table :teams do |t|
      t.integer :sport_id, :null => false
      t.string :abbrev, :null => false
      t.string :name, :null => false
      t.string :conference, :null => false
      t.string :division, :null => false
      t.string :market
      t.string :state
      t.string :country
      t.decimal :lat
      t.decimal :long
      t.text :standings
      t.timestamps
    end

  end
end
