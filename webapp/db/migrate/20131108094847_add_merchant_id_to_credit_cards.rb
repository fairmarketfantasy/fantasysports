class AddMerchantIdToCreditCards < ActiveRecord::Migration
  def change
    add_column :credit_cards, :network_merchant_id, :string
  end
end
