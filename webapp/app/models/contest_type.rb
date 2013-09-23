class ContestTypeValidator < ActiveModel::Validator
  def validate(record)
    total_payout = record.get_payout_structure.sum
    total_buy_in = record.max_entries * record.buy_in
    if record.max_entries == 0
      if total_payout > 10000000 # Catch the crazies
        record.errors[:payout_structure] = "Payout structure adds to more than  100k"
      end
    elsif total_payout != total_buy_in - total_buy_in * record.rake
      record.errors[:payout_structure] = "Payout structure doesn't equal max_entries * buy_in - rake * max_entries * buy_in"
    end
  end
end
class ContestType < ActiveRecord::Base
  attr_protected
  belongs_to :market
  belongs_to :user
  has_many :contests
  has_many :rosters

  validates_with ContestTypeValidator

  scope :public, -> { where('private = false OR private IS NULL') }
  # TODO: validate payout structure, ensure rake isn't settable

  def get_payout_structure
    @payout_structure ||= JSON.load(self.payout_structure)
  end

  def payout_structure=(json)
    @payout_structure = nil
    super
  end

  # USE RANK_PAYMENT INSTEAD, IT HANDLES EDGE CASES
  def payout_for_rank(rank)
    get_payout_structure[rank-1]
  end

  #figure out how much each rank gets -- tricky only because of ties
  def rank_payment(ranks)
    rank_payment = Hash.new(0)
    get_payout_structure.each_with_index do |payment, i|
      rank_payment[ranks[i]] += payment
    end
    return rank_payment
  end
end
