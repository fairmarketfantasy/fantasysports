class TransactionRecordValidator < ActiveModel::Validator
  def validate(record)
    if TransactionRecord::CONTEST_TYPES.include?(record.event) && record.contest_id.nil?
      record.errors[:contest_id] = "Contest_id is required for #{record.event} types"
    end
    if record.event =~ /referral/ && record.referred.nil?
      record.errors[:referred_id] = "Referred_id is required for #{record.event} types"
    end
  end
end

class TransactionRecord < ActiveRecord::Base
  attr_protected
  CONTEST_TYPES = %w( buy_in cancelled_roster contest_payout rake )
  validates_presence_of :user
  validates :event, inclusion: { in: CONTEST_TYPES + %w(
                                 deposit withdrawal
                                 contest_payout_bonus payout joined_grant token_buy token_buy_ios
                                 free_referral_payout paid_referral_payout referred_join_payout
                                 revert_transaction manual_payout promo monthly_user_balance monthly_taxes monthly_user_entries) }
  validates_with TransactionRecordValidator

  belongs_to :user
  belongs_to :roster
  belongs_to :contest
  belongs_to :invitation
  belongs_to :referred, :class_name => 'User'
  belongs_to :reverted_transaction, :class_name => 'TransactionRecord'

  def self.validate_contest(contest)
    return if contest.contest_type.max_entries == 0
    #debugger if contest.transaction_records.where("event != 'contest_payout_bonus'").reduce(0){|total, tr| total +=  tr.is_monthly_entry? ? -1000 * tr.amount : tr.amount } != 0
    sum = contest.transaction_records.where("event != 'contest_payout_bonus'").reduce(0){|total, tr| total +=  tr.is_monthly_entry? ? -1000 * tr.amount : tr.amount }
    if sum != 0
    #  raise "Contest #{contest.id} sums to #{sum}. Should Zero. Fucking check yo-self."
    end
  end

  def reverted?
    !TransactionRecord.where(:reverted_transaction_id => self.id).first.nil?
  end

  def revert!
    user = self.user

    opts = self.attributes.reject{|k| [:amount, :event, :user_id, :transaction_data, :created_at, :updated_at].include?(k) }
    type = case
      when self.is_monthly_winnings?
        opts[:is_monthly_winnings] = true
        'monthly_winnings'
      when self.is_monthly_entry?
        opts[:is_monthly_entry] = true
        'monthly_entry'
      when self.is_tokens?
        '' # Shouldn't hit this
      else
        'balance'
    end

    if self.amount < 0 || (amount > 0 && type == 'monthly_entry')
      user.payout(type, self.amount.abs, opts.merge(:event => 'revert_transaction', :reverted_transaction_id => self.id))
    else
      user.charge(type, self.amount.abs, opts.merge(:event => 'revert_transaction', :reverted_transaction_id => self.id))
    end
  end
end
