class AddTransactionIdToTransactionRecord < ActiveRecord::Migration
  def change
    add_column :transaction_records, :ios_transaction_id, :string
    add_column :transaction_records, :transaction_data, :text
  end
end
