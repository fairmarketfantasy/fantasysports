class AddExposedTo < ActiveRecord::Migration
  def change
    add_column :markets, :exposed_at, :timestamp, :null => false
  end
end
