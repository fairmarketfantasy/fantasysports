class AddUniqueIndexOnTeamsAbbrev < ActiveRecord::Migration
  def change
    add_index :teams, [:abbrev, :sport_id], :unique => true
  end
end
