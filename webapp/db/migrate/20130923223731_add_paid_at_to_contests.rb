class AddPaidAtToContests < ActiveRecord::Migration
  def change
    add_column :contests, :paid_at, :timestamp
  end
end
