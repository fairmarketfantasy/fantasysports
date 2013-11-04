class UpdateContestLeagues < ActiveRecord::Migration
  def change
    drop_table :league_contests
    add_column :contests, :league_id, :integer
  end
end
