class TransactionRecordValidator < ActiveModel::Validator
  def validate(record)
    if TransactionRecord::CONTEST_TYPES.include?(record.event) && record.contest_id.nil?
      record.errors[:contest_id] = "Contest_id is required for #{record.event} types"
    end
  end
end

class TransactionRecord < ActiveRecord::Base
  attr_accessible :user, :event, :amount, :roster_id, :contest_id
  CONTEST_TYPES = %w( buy_in cancelled_roster payout rake )
  validates_presence_of :user
  validates :event, inclusion: { in: CONTEST_TYPES + %w( deposit withdrawal buy_in cancelled_roster payout rake) }
  validates_with TransactionRecordValidator

  belongs_to :user
  belongs_to :roster
  belongs_to :contest

  def self.validate_contest(contest)
    return if contest.contest_type.max_entries == 0
    sum = contest.transaction_records.reduce(0){|total, tr| total += tr.amount}
    if sum != 0
      raise "Contest sums to #{sum}. Should Zero. Fucking check yo-self."
    end
  end
end
