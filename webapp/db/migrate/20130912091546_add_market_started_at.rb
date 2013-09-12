class AddMarketStartedAt < ActiveRecord::Migration
  def change
    add_column :markets, :started_at, :timestamp
  end
end
