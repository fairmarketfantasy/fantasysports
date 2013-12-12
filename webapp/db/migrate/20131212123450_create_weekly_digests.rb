class CreateWeeklyDigests < ActiveRecord::Migration
  def change
    create_table :weekly_digests do |t|
      t.string :subject
      t.datetime :deliver_at
      t.datetime :delivered_at

      t.timestamps
    end
  end
end
