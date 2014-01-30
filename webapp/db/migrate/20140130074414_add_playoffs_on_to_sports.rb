class AddPlayoffsOnToSports < ActiveRecord::Migration
  def change
    add_column :sports, :playoffs_on, :boolean, :default => false
  end
end
