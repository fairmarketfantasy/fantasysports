class MakeTeamNotNull < ActiveRecord::Migration
  def change
    change_column :players, :team, :string, :null => false
  end
end
