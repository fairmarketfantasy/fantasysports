class MovePositionsToContestTypes < ActiveRecord::Migration
  def change
    remove_column :rosters, :positions, :string
    add_column :contest_types, :positions, :string
  end
end
