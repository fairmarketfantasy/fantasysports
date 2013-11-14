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
    raise "Buy in must be between $0 and $1000" unless (0..100000).include?(record.buy_in)
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

  def duplicate_into_market(market)
    existing = market.contest_types.where(
      :name => self.name,
      :buy_in => self.buy_in,
      :salary_cap => self.salary_cap,
    ).first
    return existing if existing
    attributes = self.attributes.dup
    [:id, :created_at ].each{|attr| attributes.delete(attr) }
    attributes[:market_id] = market.id
    ContestType.create!(attributes)
  end

  # USE RANK_PAYMENT INSTEAD, IT HANDLES EDGE CASES
  def payout_for_rank(rank)
    get_payout_structure[rank-1]
  end

  #figure out how much each rank gets -- tricky only because of ties
  def rank_payment(ranks)
    rank_payment = Hash.new(0)
    payments_per_rank = if self.name == 'h2h rr'
          # Handle unfilled h2h rr. Ranks.length is number of entrants
          unplayed_games = self.max_entries - ranks.length
          get_payout_structure.slice(get_payout_structure.length-ranks.length, ranks.length).map{|amt| amt + unplayed_games * self.buy_in / (self.max_entries-1) }
        else
          get_payout_structure
        end
    payments_per_rank.each_with_index do |payment, i|
      rank_payment[ranks[i]] += payment
    end
    return rank_payment
  end
end
