class CreateTransactionTable < ActiveRecord::Migration
  def change
    create_table :transaction_records do |t|
      t.string :event, :null => false
      t.integer :user_id
      t.integer :contest_id
      t.integer :amount
    end
    add_index :transaction_records, :contest_id
    add_index :transaction_records, :user_id
  end
end
