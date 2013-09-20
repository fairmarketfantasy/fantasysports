class AddPayoutDescToContestTypes < ActiveRecord::Migration
  def change
    add_column :contest_types, :payout_description, :string, :null => false
  end
end
