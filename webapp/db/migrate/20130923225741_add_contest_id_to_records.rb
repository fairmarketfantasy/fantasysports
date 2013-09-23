class AddContestIdToRecords < ActiveRecord::Migration
  def change
    add_column :transaction_records, :contest_id, :integer
  end
end
