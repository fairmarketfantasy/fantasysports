class RenameLeagueMemberships < ActiveRecord::Migration
  def change
    rename_table :league_membership, :league_memberships
  end
end
