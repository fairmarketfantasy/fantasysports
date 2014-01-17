class AddActivatedAtToCustomerObjects < ActiveRecord::Migration
  def change
    add_column :customer_objects, :last_activated_at, :timestamp
  end
end
