class Invitation < ActiveRecord::Base
  FREE_USER_REFERRAL_PAYOUT = 0
  PAID_USER_REFERRAL_PAYOUT = 100
  attr_protected
  belongs_to :inviter, :class_name => 'User'
  belongs_to :private_contest, :class_name => 'Contest'
  belongs_to :contest_type, :class_name => 'ContestType'
  has_one :transaction_record
  validates_presence_of :inviter_id
=begin
      t.string :email, :null => false
      t.integer :inviter_id, :null => false
      t.integer :private_contest_id
      t.integer :contest_type_id
      t.string :code, :null => false
      t.boolean :redeemed, :default => false
=end
  def self.for_contest(inviter, email, contest, message)
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
    if user && contest.league
     LeagueMembership.where(:league_id => contest.league.id, :user_id => user.id).first_or_create
    end
    ContestMailer.invite_to_contest(invitation, inviter, contest, email, message).deliver!
    invitation
  end

  def self.redeem(current_user, code, contest = nil)
    inv = Invitation.where(:code => code).first
    if inv.nil? && user = User.where(:referral_code => code).first
      inv = Invitation.create!(
        email: current_user.email,
        inviter_id: user.id,
        private_contest_id: contest && contest.private? ? contest.id : nil,
        contest_type_id: contest && !contest.private? ? contest.contest_type_id : nil,
        code: SecureRandom.hex(16)
      )
    end
    raise HttpException.new(404, "No invitation found with that code") unless inv
    inv.transaction do
      if !inv.redeemed
        current_user.inviter = inv.inviter
        current_user.save!
        current_user.transaction do
          inv.inviter.payout(:balance, FREE_USER_REFERRAL_PAYOUT, :event => 'free_referral_payout', :invitation_id => inv.id, :referred_id => current_user.id)
          inv.redeemed = true
          inv.save!
        end
      end
    end
  end

  def self.redeem_paid(current_user)
    if current_user.inviter && TransactionRecord.where(:event => 'paid_referral_payout', :referred_id => current_user.id).first.nil?
      self.transaction do
        SYSTEM_USER.charge(:balance, PAID_USER_REFERRAL_PAYOUT, :event => 'paid_referral_payout', :referred_id => current_user.inviter.id)
        current_user.inviter.payout(:balance, PAID_USER_REFERRAL_PAYOUT, :event => 'paid_referral_payout', :referred_id => current_user.id)
        SYSTEM_USER.charge(:balance, PAID_USER_REFERRAL_PAYOUT, :event => 'paid_referral_payout', :referred_id => current_user.id)
        current_user.payout(:balance, PAID_USER_REFERRAL_PAYOUT, :event => 'referred_join_payout', :referred_id => current_user.id)
      end
    end
  end
end
