class AddTokensToTransactionRecords < ActiveRecord::Migration
  def change
    add_column :transaction_records, :is_tokens, :boolean, :default => false
  end
end
