class ContestType < ActiveRecord::Base
  attr_protected
  belongs_to :market
  belongs_to :user
  has_many :contests
  has_many :rosters

  scope :public, -> { where('private = false OR private IS NULL') }
  # TODO: validate payout structure, ensure rake isn't settable

  def get_payout_structure
    @payout_structure ||= JSON.load(self.payout_structure)
  end

  def payout_structure=(json)
    @payout_structure = nil
    super
  end

  def payout_for_rank(rank)
    get_payout_structure[rank]
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
