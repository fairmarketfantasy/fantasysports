class AddQuantityFieldsToStatEvents < ActiveRecord::Migration
  def change
    add_column :stat_events, :quantity, :decimal
    add_column :stat_events, :points_per, :decimal
  end
end
