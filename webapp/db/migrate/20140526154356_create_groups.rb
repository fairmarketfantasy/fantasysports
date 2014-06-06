class CreateGroups < ActiveRecord::Migration
  def change
    create_table :groups do |t|
      t.integer :sport_id
      t.string :name

      t.timestamps
    end

    add_index :groups, [:name, :sport_id], :unique => true

    add_column :teams, :group_id, :integer
    add_index :teams, :group_id
  end
end
