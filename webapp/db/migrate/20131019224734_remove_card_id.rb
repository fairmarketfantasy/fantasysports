class RemoveCardId < ActiveRecord::Migration
  def change
    remove_column :credit_cards, :card_id, :string
  end
end
