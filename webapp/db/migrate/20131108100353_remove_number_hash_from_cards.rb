class RemoveNumberHashFromCards < ActiveRecord::Migration
  def change
    remove_column :credit_cards, :card_number_hash, :string
  end
end
