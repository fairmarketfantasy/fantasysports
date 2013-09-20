class Contest < ActiveRecord::Base
  attr_protected
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User"
  belongs_to :contest_type

  self.inheritance_column = :_type_disabled

  # after_create :create_owners_roster!
  # before_save :set_invitation_code, on: :create

  validates :owner_id, :contest_type_id, :buy_in, :market_id, presence: true

  def invite(email)
    self.save if self.new_record?
    ContestMailer.invite(self, email).deliver
  end

  def submit_roster(roster)
    raise "Only in progress rosters may be submitted" unless roster.state != 'in_progress'
    Contest.transaction do
      roster.state = 'submitted'
      # we dock the balance on roster create now
      # roster.owner.customer_object.decrease_balance(roster.buy_in, 'buy_in')
      roster.save!
    end
  end

  #creates a roster for the owner and creates an invitation code
  def make_private
    set_invitation_code
    create_owners_roster!
  end

  #pays owners of rosters according to their place in the contest
  def payday!
    self.with_lock do
      rosters = self.rosters.order("contest_rank ASC")
      ranks = rosters.collect(&:contest_rank)
      
      #figure out how much each rank gets -- tricky only because of ties
      rank_payment = contest_type.rank_payment(ranks)

      #organize rosters by rank
      rosters_by_rank = Contest._rosters_by_rank(rosters)

      #for each rank, make payments
      rosters_by_rank.each_pair do |rank, rosters|
        payment = rank_payment[rank]
        if payment.nil?
          roster.paid_at = Time.new
          roster.amount_paid = 0
          roster.state = 'finished'
          roster.save!
          next
        end
        payment_per_roster = Float(payment) / rosters.length
        rosters.each do |roster|
          # puts "roster #{roster.id} won #{payment_per_roster}!"
          roster.owner.customer_object.increase_balance(payment_per_roster, 'payout', roster.id)
          roster.paid_at = Time.new
          roster.amount_paid = payment_per_roster
          roster.state = 'finished'
          roster.save!
        end
      end
    end
  end

  def self._rosters_by_rank(rosters)
    by_rank = {}
    rosters.each do |roster|
      rs = by_rank[roster.contest_rank]
      if rs.nil?
        rs = []
        by_rank[roster.contest_rank] = rs
      end
      rs << roster
    end
    return by_rank
  end

  private

    def set_invitation_code
      self.invitation_code = SecureRandom.urlsafe_base64
    end

    def create_owners_roster!
      Roster.generate(owner, contest_type)
    end

end
