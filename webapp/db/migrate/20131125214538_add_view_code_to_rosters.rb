class AddViewCodeToRosters < ActiveRecord::Migration
  def change
    add_column :rosters, :view_code, :string
  end
end
