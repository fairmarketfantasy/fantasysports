class CreateEmailUnsubscribes < ActiveRecord::Migration
  def change
    create_table :email_unsubscribes do |t|
      t.string :email, :null => false
      t.string :email_type, :null => false, :default => 'all'
      t.timestamps
    end
  end
end
