class CreateTeams < ActiveRecord::Migration
  def change
    create_table :teams do |t|
      t.integer :sport_id, :null => false
      t.string :name, :null => false
      t.string :state
      t.string :country
      t.decimal :lat
      t.decimal :long
      t.timestamps
    end
  end
end
