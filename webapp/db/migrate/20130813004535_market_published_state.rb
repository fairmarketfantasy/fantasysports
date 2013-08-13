class MarketPublishedState < ActiveRecord::Migration
  def change
    rename_column :markets, :exposed_at, :published_at
    add_column :markets, :state, :string
  end
end
