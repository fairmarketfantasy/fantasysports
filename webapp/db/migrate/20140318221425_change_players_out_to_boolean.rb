class ChangePlayersOutToBoolean < ActiveRecord::Migration
  def change
    remove_column :players, :out, :string
    add_column :players, :out, :boolean
  end
end
