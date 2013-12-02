class CreatePromos < ActiveRecord::Migration
  def change
    create_table :promos do |t|
      t.string :code, :null => false
      t.timestamp :valid_until
      t.integer :cents, :null => false, :default => 0
      t.integer :tokens, :null => false, :default => 0
      t.boolean :only_new_users, :null => false, :default => false
      t.timestamps
    end
    create_table :promo_redemptions do |t|
      t.integer :promo_id, :null => false
      t.integer :user_id, :null => false
      t.timestamps
    end
    add_index :promo_redemptions, [:user_id, :promo_id], :unique => true
    add_index :promos, :code, :unique => true
    add_column :transaction_records, :promo_id, :integer
  end
end
