class AddCardIdToCards < ActiveRecord::Migration
  def change
    add_column :credit_cards, :paypal_card_id, :string
  end
end
