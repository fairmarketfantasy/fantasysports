class AddExpectedPayoutToRosters < ActiveRecord::Migration
  def change
    add_column :rosters, :expected_payout, :integer, :null => false, :default => 0
  end
end
