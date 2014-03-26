class AddMonthlyEntriesCounterToCustomerObject < ActiveRecord::Migration
  def change
    add_column :customer_objects, :monthly_entries_counter, :integer, :null => false, :default => 0
  end
end
