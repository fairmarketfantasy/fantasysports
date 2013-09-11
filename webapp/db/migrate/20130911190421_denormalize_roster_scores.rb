class DenormalizeRosterScores < ActiveRecord::Migration
  def change
    rename_column :rosters, :final_points, :score
    rename_column :rosters, :finish_place, :contest_rank
  end
end
