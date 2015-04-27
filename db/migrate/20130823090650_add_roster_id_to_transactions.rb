class AddRosterIdToTransactions < ActiveRecord::Migration
  def change
    rename_column :transaction_records, :contest_id, :roster_id
  end
end
