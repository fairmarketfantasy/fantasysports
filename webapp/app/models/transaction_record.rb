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
  CONTEST_TYPES = %w( buy_in cancelled_roster payout rake )
  validates_presence_of :user
  validates :event, inclusion: { in: CONTEST_TYPES + %w( 
                                 deposit withdrawal buy_in cancelled_roster 
                                 payout rake joined_grant token_buy token_buy_ios 
                                 free_referral_payout paid_referral_payout referred_join_payout 
                                 revert_transaction manual_payout) }
  validates_with TransactionRecordValidator

  belongs_to :user
  belongs_to :roster
  belongs_to :contest
  belongs_to :invitation
  belongs_to :referred, :class_name => 'User'
  belongs_to :reverted_transaction, :class_name => 'TransactionRecord'

  def self.validate_contest(contest)
    return if contest.contest_type.max_entries == 0
    sum = contest.transaction_records.reduce(0){|total, tr| total += tr.amount}
    if sum != 0
      debugger
      raise "Contest #{contest.id} sums to #{sum}. Should Zero. Fucking check yo-self."
    end
  end

  def reverted?
    !TransactionRecord.where(:reverted_transaction_id => self.id).first.nil?
  end

  def revert!
    user = self.user

    opts = self.attributes
    ['id', 'event', 'amount', 'is_tokens'].each do |a|
      opts.delete(a)
    end

    if self.amount < 0
      user.payout(self.amount.abs, self.is_tokens, opts.merge(:event => 'revert_transaction', :reverted_transaction_id => self.id))
    else
      user.charge(self.amount.abs, self.is_tokens, opts.merge(:event => 'revert_transaction', :reverted_transaction_id => self.id))
    end
  end
end
