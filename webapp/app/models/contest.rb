class Contest < ActiveRecord::Base
  attr_protected
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User"
  belongs_to :contest_type

  before_save :set_invitation_code, on: :create

  validates :owner_id, :contest_type_id, :buy_in, :market_id, presence: true

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
  def self.create_private_contest(opts) 
    market = Market.where(:id => opts[:market_id], state: ['published', 'opened']).first
    raise "Market must be active to create a contest" unless market
    raise "It's too close to market close to create a contest" if Time.new + 5.minutes > market.closed_at
    # H2H don't have to be an existing contst type, and in fact are always new ones so that if your challenged person doesn't accept, the roster is cancelled
    if opts[:contest_type_id == 'h2h']
      buy_in       = opts[:buy_in]
      rake = 0.03
      contest_type = ContestType.create!(
        :market_id => market.id,
        :name => 'custom h2h',
        :description => 'custom h2h',
        :max_entries => 2,
        :buy_in => opts[:buy_in],
        :rake => rake,
        :payout_structure => [buy_in - buy_in * rake * 2].to_json,
        :user_id => opts[:user_id],
        :private => true,
        :salary_cap => opts[:salary_cap],
        :payout_description => "Winner take all"
      )
    else
      contest_type = ContestType.find(opts[:contest_type_id])
    end

    contest = Contest.create!(
      market: market,
      owner_id: opts[:user_id],
      user_cap: contest_type.max_entries,
      buy_in: contest_type.buy_in,
      contest_type: contest_type,
      private: true
    )

  end

  def rake_amount
    self.num_rosters * self.contest_type.buy_in * contest_type.rake
  end

  #pays owners of rosters according to their place in the contest
  def payday!
    self.with_lock do
      raise if self.paid_at
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
          roster.owner.customer_object.increase_balance(payment_per_roster, 'payout', roster.id, self.id)
          roster.paid_at = Time.new
          roster.amount_paid = payment_per_roster
          roster.state = 'finished'
          roster.save!
        end
      end
      TransactionRecord.create!(:user => SYSTEM_USER, :amount => self.rake_amount, :event => 'rake', :contest_id => self.id)
      self.paid_at = Time.new
      self.save!
      TransactionRecord.validate_contest(self)
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

end
