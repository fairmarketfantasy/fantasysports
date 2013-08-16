class CreateCustomerObjects < ActiveRecord::Migration
  def change
    create_table :customer_objects do |t|
      t.string  :stripe_id,      null: false
      t.integer :user_id,        null: false
      t.timestamps
    end
  end
end
