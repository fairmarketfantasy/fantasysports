class Contest < ActiveRecord::Base
  attr_protected
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User"
  belongs_to :contest_type
  belongs_to :league

  before_create :set_invitation_code

  validates :owner_id, :contest_type_id, :buy_in, :market_id, presence: true

  #creates a roster for the owner and creates an invitation code
  def self.create_private_contest(opts)
    market = Market.where(:id => opts[:market_id], state: ['published', 'opened']).first
    raise HttpException.new(409, "Sorry, that market couldn't be found or is no longer active. Try a later one.") unless market
    raise HttpException.new(409, "Sorry, it's too close to market close to create a contest. Try a later one.") if Time.new + 5.minutes > market.closed_at
    # H2H don't have to be an existing contst type, and in fact are always new ones so that if your challenged person doesn't accept, the roster is cancelled
    existing_contest_type = market.contest_types.where(:name => opts[:type], :buy_in => opts[:buy_in], :takes_tokens => !!opts[:takes_tokens]).first
    if opts[:type] == 'h2h' && existing_contest_type.nil?
      buy_in       = opts[:buy_in]
      rake = 0.03

      contest_type = ContestType.create!(
        :market_id => market.id,
        :name => 'h2h',
        :description => 'custom h2h contest',
        :max_entries => 2,
        :buy_in => opts[:buy_in],
        :rake => rake,
        :payout_structure => [2 * buy_in - buy_in * rake * 2].to_json,
        :user_id => opts[:user_id],
        :private => true,
        :salary_cap => opts[:salary_cap] || 100000,
        :payout_description => "Winner take all",
        :takes_tokens => opts[:takes_tokens] || false,
      )
    else
      contest_type = existing_contest_type
      raise HttpException.new(404, "No such contest type found") unless contest_type
    end

    if opts[:league_id] || opts[:league_name]
      opts[:max_entries] = contest_type.max_entries
      opts[:takes_tokens] = contest_type.takes_tokens
      opts[:user] = User.find(opts[:user_id])
      opts[:market] = market
      league = League.find_or_create_from_opts(opts)
    end

    contest = Contest.create!(
      market: market,
      owner_id: opts[:user_id],
      user_cap: contest_type.max_entries,
      buy_in: contest_type.buy_in,
      contest_type: contest_type,
      private: true,
      league_id: league && league.id,
    )
  end

  def num_winners
    self.contest_type.get_payout_structure.length
  end

  def rake_amount
    rake = self.num_rosters * self.contest_type.buy_in * contest_type.rake
    if contest_type.name == 'h2h rr'
      per_game_buy_in = self.contest_type.buy_in / (self.contest_type.max_entries - 1)
      rake = (self.num_rosters-1) * per_game_buy_in * num_rosters * contest_type.rake
    end
    rake
  end

  #pays owners of rosters according to their place in the contest
  def payday!
    self.with_lock do
      return if self.paid_at && Market.override_close
      raise if self.paid_at || self.cancelled_at
      puts "Payday! for contest #{self.id}"
      Rails.logger.debug("Payday! for contest #{self.id}")
      rosters = self.rosters.order("contest_rank ASC")

      ranks = rosters.collect(&:contest_rank)

      #figure out how much each rank gets -- tricky only because of ties
      rank_payment = contest_type.rank_payment(ranks)
      #organize rosters by rank
      rosters_by_rank = Contest._rosters_by_rank(rosters)

      #for each rank, make payments
      rosters_by_rank.each_pair do |rank, ranked_rosters|
        payment = rank_payment[rank]
        payment_per_roster = Float(payment) / ranked_rosters.length
        payments_for_rosters = rounded_payouts(payment_per_roster, ranked_rosters.length)

        ranked_rosters.each_with_index do |roster, i|
          roster.set_records!
          roster.paid_at = Time.new
          roster.state = 'finished'
          if payment.nil?
            roster.amount_paid = 0
            roster.save!
            next
          end
          # puts "roster #{roster.id} won #{payment_per_roster}!"
          roster.owner.payout(payments_for_rosters[i], self.contest_type.takes_tokens?, :event => 'payout', :roster_id => roster.id, :contest_id => self.id)
          roster.amount_paid = payments_for_rosters[i]
          roster.save!
        end
      end
      SYSTEM_USER.payout(self.rake_amount, self.contest_type.takes_tokens?, :event => 'rake', :roster_id => nil, :contest_id => self.id)
      self.paid_at = Time.new

      self.save!
      TransactionRecord.validate_contest(self)
    end
  end

  def revert_payday!
    self.with_lock do
      raise if self.paid_at.nil?
      self.paid_at = nil
      TransactionRecord.validate_contest(self)
      TransactionRecord.where(:contest_id => self.id).each do |tr|
        next if tr.reverted? || tr.event == 'buy_in'#TransactionRecord::CONTEST_TYPES.include?(tr.event)
        tr.revert!
      end
      TransactionRecord.validate_contest(self)
      self.save!
      self.market.tabulate_scores
    end
  end

  def cancel! # Only used for unfilled h2h contests
    raise "Not a h2h or h2h has players, can't cancel" unless contest_type.name =~ /h2h/ && num_rosters == 1
    self.rosters.each{|r| r.cancel!("No opponent found for H2H") }
    self.cancelled_at = Time.new
    self.save!
    TransactionRecord.validate_contest(self)
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

  def fill_with_rosters(percentage = 1.0)
    contest_cap = if self.user_cap == 0
        JSON.parse(self.contest_type.payout_structure).sum  * self.contest_type.rake / self.buy_in
      else
        self.user_cap
      end
    fill_number = contest_cap * percentage
    rosters = [fill_number - self.num_rosters, 0].max.to_i
    rosters.times do
      roster = Roster.generate(SYSTEM_USER, self.contest_type)
      roster.contest_id = self.id
      roster.is_generated = true
      roster.save!
      roster.fill_pseudo_randomly3
      roster.submit!
    end
  end

  private

  def set_invitation_code
    self.invitation_code ||= SecureRandom.urlsafe_base64
  end

    def rounded_payouts(payout_per, number)
      total = (payout_per * number).to_i
      payouts = Array.new(number, payout_per.floor)
      sum = payouts.reduce(&:+)
      (0..(total - sum-1)).each do |i|
        payouts[i] += 1
      end
      payouts
    end

end
