class AddContestType < ActiveRecord::Migration
  def change
  	create_table :contest_types do |t|
  		t.integer :market_id, :null => false
  		t.string :name, :null => false
  		t.text :description, :null => true
  		t.integer :max_entries, :null => false
  		t.integer :buy_in, :null => false
  		t.decimal :rake, :null => false
  		t.text :payout_structure, :null => false
  		t.integer :user_id, :null => true
  		t.boolean :private, :null => true
  	end
  	remove_column :rosters, :contest_type, :string
  	add_column :rosters, :contest_type_id, :integer, :null => false, :default => 0
  	add_index :rosters, :contest_type_id
  	add_index :contest_types, :market_id
  end
end
