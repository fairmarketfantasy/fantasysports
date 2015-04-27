class CreateMembers < ActiveRecord::Migration
  def change
    create_table :members do |t|
      t.integer :competition_id
      t.integer :memberable_id
      t.string :memberable_type
      t.integer :rank

      t.timestamps
    end
  end
end
