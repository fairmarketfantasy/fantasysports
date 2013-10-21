class SwapStripeWithPaypalRecipients < ActiveRecord::Migration
  def change
    remove_column :recipients, :stripe_id
    add_column :recipients, :paypal_email, :string, :null => false
  end
end
