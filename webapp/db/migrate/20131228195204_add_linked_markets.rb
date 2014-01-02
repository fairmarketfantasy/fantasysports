class AddLinkedMarkets < ActiveRecord::Migration
  def change
    add_column :markets, :linked_market_id, :integer
  end
end
