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

  # NOENTRY TODO: REMOVE CUSTOM H2H amounts
  #creates a roster for the owner and creates an invitation code
  def self.create_private_contest(opts)
    market = Market.where(:id => opts[:market_id], state: ['published', 'opened']).first
    raise HttpException.new(409, "Sorry, that market couldn't be found or is no longer active. Try a later one.") unless market
    raise HttpException.new(409, "Sorry, it's too close to market close to create a contest. Try a later one.") if Time.new + 5.minutes > market.closed_at
    # H2H don't have to be an existing contst type, and in fact are always new ones so that if your challenged person doesn't accept, the roster is cancelled
    contest_type = market.contest_types.where(:name => opts[:type]).first
    raise HttpException.new(404, "No such contest type found") unless contest_type
    raise HttpException.new(409, "You can't create a private lollapalloza") if contest_type.name =~ /k/

    if opts[:league_id] || opts[:league_name]
      opts[:max_entries] = contest_type.max_entries
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

  def perfect_score
    position_hash = {}
    total = 0
    contest_type.position_array.each do |p|
      position_hash[p] ||= 0
      position_hash[p] += 1
      total += 1
    end
    score = 0
    # TODO: now that players can have multiple positions, this is approximate.  Making it correct is still probably worthwhile.
    # This is acually an NP complete Set Covering problem with small sets, so it should be brute forceable without much trouble.
    # http://en.wikipedia.org/wiki/Set_cover_problem
    players = []
    self.market.market_players.select('market_players.*, player_positions.position').joins('JOIN player_positions ON market_players.player_id=player_positions.player_id').order('score desc').each do |mp|
      next unless mp.player # Hacky as shit, this should never happen
      pos = mp[:position]
      if position_hash[pos] && position_hash[pos] > 0 && !players.include?(mp.player_id)
        total  -= 1
        position_hash[pos] -= 1
        players += [mp.player_id]
        score += mp.score
        return score if total == 0
      end
    end
    score
  end

  def submitted_rosters_by_rank(&block)
    rosters = self.rosters.submitted.order("contest_rank ASC")
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
        yield roster, rank, payments_for_rosters[i] #roster, rank, expected_payout
      end
    end
  end

  def set_payouts!
    self.with_lock do
      submitted_rosters_by_rank do |roster, rank, payment|
        roster.update_attribute(:expected_payout, payment)
      end
    end
  end

  #pays owners of rosters according to their place in the contest
  def payday!
    self.with_lock do
      return if self.paid_at #&& Market.override_close
      raise if self.paid_at || self.cancelled_at
      puts "Payday! for contest #{self.id}"
      Rails.logger.debug("Payday! for contest #{self.id}")
      submitted_rosters_by_rank do |roster, rank, payment|
        roster.set_records!
        roster.paid_at = Time.new
        roster.state = 'finished'
        if payment.nil?
          roster.amount_paid = 0
          roster.save!
          next
        end
        # puts "roster #{roster.id} won #{payment_per_roster}!"
        roster.owner.payout(:monthly_winnings, payment, :event => 'contest_payout', :roster_id => roster.id, :contest_id => self.id)
        roster.owner.payout(:monthly_winnings, payment * (roster.owner.customer_object.contest_winnings_multiplier - 1), :event => 'contest_payout_bonus', :roster_id => roster.id, :contest_id => self.id)
        roster.amount_paid = payment
        roster.save!
      end
      # NOEENTRY TODO: Don't tax system user's monthly payouts
      SYSTEM_USER.payout(:monthly_winnings, self.contest_type.rake, :event => 'rake', :roster_id => nil, :contest_id => self.id)
      self.paid_at = Time.new

      self.save!
      TransactionRecord.validate_contest(self)
    end
  end

  def revert_payday!
    self.with_lock do
      raise if self.paid_at.nil?
      self.paid_at = nil
      self.rosters.finished.update_all(:state => 'submitted')
      TransactionRecord.validate_contest(self)
      TransactionRecord.where(:contest_id => self.id).each do |tr|
        next if tr.reverted? || tr.event == 'buy_in'#TransactionRecord::CONTEST_TYPES.include?(tr.event)
        tr.revert!
      end
      self.save!
      self.market.tabulate_scores
    end
  end

  def cancel! # Only used for unfilled h2h contests
    raise "Not a h2h or h2h has players, can't cancel" unless contest_type.name =~ /h2h/i && num_rosters == 1
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
      roster.fill_pseudo_randomly5(false)
      roster.submit!
    end
  end

  def fill_reinforced_rosters
    self.rosters.where('is_generated').each do |roster|
      roster.fill_pseudo_randomly5(false)
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
