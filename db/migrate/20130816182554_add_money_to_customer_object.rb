class AddMoneyToCustomerObject < ActiveRecord::Migration
  def change
    add_column :customer_objects, :balance, :integer, default: 0
  end
end
