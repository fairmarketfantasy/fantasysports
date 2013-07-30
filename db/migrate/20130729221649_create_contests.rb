class CreateContests < ActiveRecord::Migration
  def change
    create_table :contests do |t|
      t.integer :owner, :null => false
      t.timestamp :start_time
      t.timestamp :end_time
      t.timestamps
    end
  end
end
