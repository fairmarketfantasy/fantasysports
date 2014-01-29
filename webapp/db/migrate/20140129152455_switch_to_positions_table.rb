class SwitchToPositionsTable < ActiveRecord::Migration
  def change
    remove_column :players, :position, :string
  end
end
