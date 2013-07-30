class CreateSports < ActiveRecord::Migration
  def change
    create_table :sports do |t|
      t.string :name, :null => false
      t.timestamps
    end
    add_index :sports, :name, :unique => true
  end
end
