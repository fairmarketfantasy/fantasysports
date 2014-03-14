class AddOutToPlayers < ActiveRecord::Migration
  def change
    add_column :players, :out, :string
  end
end
