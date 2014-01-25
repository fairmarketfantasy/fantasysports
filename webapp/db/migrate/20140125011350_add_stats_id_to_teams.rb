class AddStatsIdToTeams < ActiveRecord::Migration
  def change
    add_column :teams, :stats_id, :string, :default => ""
    add_index :teams, :stats_id # Not unique because football doesn't fucking have them
  end
end
