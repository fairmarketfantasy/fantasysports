class AddPushDevices < ActiveRecord::Migration
  def change
    create_table :push_devices do |t|
      t.string :device_id
      t.string :device_type
      t.integer :user_id
      t.string :token
      t.string :environment
      t.timestamps
    end
  end
end
