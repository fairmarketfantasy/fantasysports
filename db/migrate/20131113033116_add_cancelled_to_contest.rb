class AddCancelledToContest < ActiveRecord::Migration
  def change
    add_column :contests, :cancelled_at, :timestamp
  end
end
