class AddRosterFillingToMarkets < ActiveRecord::Migration
  def change
    add_column :markets, :fill_roster_times, :text
  end
end
