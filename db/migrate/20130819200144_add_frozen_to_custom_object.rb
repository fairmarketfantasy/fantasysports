class AddFrozenToCustomObject < ActiveRecord::Migration
  def change
    add_column :customer_objects, :locked,        :boolean, null: false, default: false
    add_column :customer_objects, :locked_reason, :text
  end
end
