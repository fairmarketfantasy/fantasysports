class AddCardsForPaypal < ActiveRecord::Migration
  def change
    add_column :customer_objects, :default_card_id, :integer
    add_column :credit_cards, :obscured_number, :string
    add_column :credit_cards, :first_name, :string
    add_column :credit_cards, :last_name, :string
    add_column :credit_cards, :type, :string
    add_column :credit_cards, :expires, :date
  end
end
