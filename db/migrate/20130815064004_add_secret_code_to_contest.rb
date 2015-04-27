class AddSecretCodeToContest < ActiveRecord::Migration
  def up
    add_column :contests, :invitation_code, :string
    Contest.all.each do |con|
      con.invitation_code = SecureRandom.urlsafe_base64
      con.save!
    end
    change_column :contests, :invitation_code, :string, null: false
  end

  def down
    remove_column :contests, :invitation_code
  end
end
