class CreateSentEmails < ActiveRecord::Migration
  def change
    create_table :sent_emails do |t|
      t.integer :user_id, :null => false
      t.string :email_type, :null => false
      t.text :email_content, :null => false
      t.timestamp :sent_at, :null => false
      t.timestamps
    end
    add_index :sent_emails, [:user_id, :email_type]
    add_index :sent_emails, :sent_at
  end
end
