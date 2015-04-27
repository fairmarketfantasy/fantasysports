class AddInvitationIdToTransactions < ActiveRecord::Migration
  def change
    add_column :transaction_records, :invitation_id, :integer
  end
end
