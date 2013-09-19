class AddCardIdToCreditCards < ActiveRecord::Migration
  def change
    add_column :credit_cards, :card_id, :string, null: false
  end
end
