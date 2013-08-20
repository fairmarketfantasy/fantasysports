class AddTeamToPlayer < ActiveRecord::Migration
  def change
    remove_column :players, :team_id, :integer
    add_column :players, :team, :string
    add_index :players, :team
  end
end
