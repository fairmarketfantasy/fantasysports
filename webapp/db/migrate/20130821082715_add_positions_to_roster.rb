class AddPositionsToRoster < ActiveRecord::Migration
  def change
    add_column :rosters, :positions, :string
  end
end
