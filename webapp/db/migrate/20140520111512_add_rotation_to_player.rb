class AddRotationToPlayer < ActiveRecord::Migration
  def change
    add_column :players, :rotation, :integer

    add_index :players, :rotation
    add_index :players, :money_line
  end
end
