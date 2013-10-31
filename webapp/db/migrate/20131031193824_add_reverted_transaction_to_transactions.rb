class AddRevertedTransactionToTransactions < ActiveRecord::Migration
  def change
    add_column :transaction_records, :reverted_transaction_id, :integer
  end
end
