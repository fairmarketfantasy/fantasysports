class RemoveStripeId < ActiveRecord::Migration
  def change
    remove_column :customer_objects, :stripe_id
  end
end
