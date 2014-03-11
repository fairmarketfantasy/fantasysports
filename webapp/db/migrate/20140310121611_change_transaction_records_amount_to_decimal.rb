class ChangeTransactionRecordsAmountToDecimal < ActiveRecord::Migration
  def change
    change_column :transaction_records, :amount, :decimal
    change_column :customer_objects, :monthly_contest_entries, :decimal, :default => 0.0
    change_column :customer_objects, :contest_entries_deficit, :decimal, :default => 0.0
  end
end
