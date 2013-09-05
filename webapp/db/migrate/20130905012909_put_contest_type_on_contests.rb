class PutContestTypeOnContests < ActiveRecord::Migration
  def change
    remove_column :contests, :type, :string
    add_column :contests, :contest_type_id, :integer, null: false
  end
end
