class AddDayToLeagues < ActiveRecord::Migration
  def change
    add_column :leagues, :start_day, :integer
    add_column :leagues, :duration, :string
  end
end
