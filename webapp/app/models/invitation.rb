class Invitation < ActiveRecord::Base
  attr_protected
  belongs_to :inviter, :class_name => 'User'
  belongs_to :private_contest, :class_name => 'Contest'
  belongs_to :contest_type, :class_name => 'ContestType'
  validates_presence_of :inviter_id
=begin
      t.string :email, :null => false
      t.integer :inviter_id, :null => false
      t.integer :private_contest_id
      t.integer :contest_type_id
      t.string :code, :null => false
      t.boolean :redeemed, :default => false
=end
  def self.for_contest(inviter, email, contest)
    user = User.find_by_email(email)
    invitation = nil
    if user.nil?
      invitation = Invitation.create!(
        email: email,
        inviter_id: inviter.id,
        private_contest_id: contest.private? ? contest.id : nil,
        contest_type_id: contest.private? ? nil : contest.contest_type_id,
        code: SecureRandom.hex(16)
      )
    end
    ContestMailer.invite_to_contest(invitation, inviter, contest, email)
  end

end
