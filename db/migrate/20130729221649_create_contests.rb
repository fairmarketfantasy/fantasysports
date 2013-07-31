class CreateContests < ActiveRecord::Migration
  def change
    create_table :contests do |t|
      t.integer :owner, :null => false
      t.string :type, :null => false
      t.integer :buy_in, :null => false
      t.integer :user_cap
      t.timestamp :start_time
      t.timestamp :end_time
      t.timestamps
    end
  end
end
