class ChangeMarketTimes < ActiveRecord::Migration
  def change
    change_column :markets, :opened_at, :timestamp, :null => true
  end
end
