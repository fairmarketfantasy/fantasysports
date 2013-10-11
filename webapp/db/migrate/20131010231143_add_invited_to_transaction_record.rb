class AddInvitedToTransactionRecord < ActiveRecord::Migration
  def change
    add_column :transaction_records, :referred_id, :integer
  end
end
