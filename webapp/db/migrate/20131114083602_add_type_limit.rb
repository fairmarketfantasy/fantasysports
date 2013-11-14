class AddTypeLimit < ActiveRecord::Migration
  def change
    add_column :contest_types, :limit, :integer
  end
end
