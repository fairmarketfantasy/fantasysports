class AddTimestampsToTransactionRecords < ActiveRecord::Migration
  def change
    add_column :transaction_records, :created_at, :timestamp
    add_column :transaction_records, :updated_at, :timestamp
  end
end
