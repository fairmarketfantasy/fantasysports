class CreateInvitations < ActiveRecord::Migration
  def change
    create_table :invitations do |t|
      t.string :email, :null => false
      t.integer :inviter_id, :null => false
      t.integer :private_contest_id
      t.integer :contest_type_id
      t.string :code, :null => false
      t.boolean :redeemed, :default => false
      t.timestamps
    end
  end
end
