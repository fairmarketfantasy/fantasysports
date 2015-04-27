class AddStripeRecipientIdToCustomerObject < ActiveRecord::Migration
  def change
    create_table :recipients do |t|
      t.string  :stripe_id,   null: false
      t.integer :user_id,     null: false
      t.string  :legal_name,  null: false
      t.string  :routing,     null: false
      t.string  :account_num, null: false
    end
  end
end
