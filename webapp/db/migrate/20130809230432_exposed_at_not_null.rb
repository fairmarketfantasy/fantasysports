class ExposedAtNotNull < ActiveRecord::Migration
  def change
  	change_column :markets, :exposed_at, :timestamp, :null => true
  end
end
