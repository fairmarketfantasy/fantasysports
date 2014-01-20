class Roster < ActiveRecord::Base
  USER_BONUSES = { 'twitter_follow' =>  1}
  ROSTER_BONUSES = { 'twitter_share' => 1, 'facebook_share' => 1}

  attr_protected
  def perfect_score; self[:perfect_score]; end

  has_and_belongs_to_many :players, -> { select(Player.with_purchase_price.select_values) }, join_table: 'rosters_players'
  has_many :rosters_players
  belongs_to :market
  belongs_to :contest
  belongs_to :contest_type
  belongs_to :owner, class_name: "User", foreign_key: :owner_id
  has_many :market_orders

  validates :state, :inclusion => {in: %w( in_progress cancelled submitted finished) }

  validates :owner_id, :market_id, :buy_in, :remaining_salary, :contest_type_id, :state, presence: true

  before_create :set_view_code
  before_destroy :pre_destroy

  scope :over, -> { where(state: ['cancelled', 'finished'])}
  scope :active, -> { where(state: ['in_progress', 'submitted'])}
  scope :submitted, -> { where(state: ['submitted'])}
  scope :finished, -> { where(state: ['finished'])}
  scope :with_perfect_score, ->(score) { select("rosters.*, #{score.to_f} as perfect_score") }


  def players_with_prices
    self.class.uncached do
      self.players.select('players.*, rosters_players.purchase_price, mp.*').joins(
        # Not user input params
        "JOIN market_prices_for_players(#{self.market_id}, #{self.buy_in}, #{self.rosters_players.map(&:player_id).unshift(-1).join(', ') }) mp ON mp.player_id=players.id")
      #Player.find_by_sql("select * from roster_prices(#{self.id})")
    end
  end

  def purchasable_players
    self.class.uncached do
      Player.purchasable_for_roster(self)
    end
  end

  def sellable_players
    Player.with_sell_prices(self).sellable
  end

  def market_players
    MarketPlayer.where(:market_id => self.market_id, :player_stats_id => self.rosters_players.map(&:player_stats_id))
  end

  # create a roster. does not deduct funds until roster is submitted.
  def self.generate(user, contest_type)
    raise HttpException.new(403, "This market is closed") unless contest_type.market.accepting_rosters?
    user.in_progress_roster.destroy if user.in_progress_roster

    Roster.create!(
      :owner_id => user.id,
      :market_id => contest_type.market_id,
      :contest_type_id => contest_type.id,
      :takes_tokens => contest_type.takes_tokens,
      :buy_in => contest_type.buy_in,
      :remaining_salary => contest_type.salary_cap,
      :state => 'in_progress',
    )
  end

  def set_view_code
    self.view_code = SecureRandom.urlsafe_base64
  end

  def build_from_existing(roster)
    roster.players.each do |player|
      self.add_player(player)
    end
  end

=begin
  There are essentially 4 active states for rosters and markets to be in:
  - in_progress, published
  - submitted, published
  - in_progress, opened
  - submitted, opened
  Only in the last state are price differentials important.  
  That also means that in cases 1-3 remaining salary is determined by the buy_price of the roster's players
=end
  def remaining_salary
    # Factory girl gets all pissy if you don't check for id here
    if self.id && (self.state == 'in_progress' || self.market.state == 'published')
      salary = self.contest_type.salary_cap
      self.players_with_prices.each do |p|
        salary -= p.buy_price
      end
      salary
    else
      self[:remaining_salary]
    end
  end

  def set_records!
    if self.cancelled?
      self.wins = 0
      self.losses = 0
    else
      rk = RecordKeeper.for_roster(self)
      self.wins = rk.wins
      self.losses = rk.losses
    end
  end

  #set the state to 'submitted'. If it's in a private contest, increment the number of 
  #rosters in the private contest. If not, enter it into a public contest, creating a new one if necessary.
  def submit!(charge = true)
    #buy all the players on the roster. This sql function handles all of that.
    raise HttpException.new(402, "Unpaid subscription!") if charge && !owner.active_account?
      #purchase all the players and update roster state to submitted

      set_contest = contest
      #enter contest
      contest_type.with_lock do #prevents creation of contests of the same type at the same time
        Roster.find_by_sql("SELECT * FROM submit_roster(#{self.id})")
        reload
        if set_contest.nil?
          #enter roster into public contest
          set_contest = Contest.where("contest_type_id = ?
            AND (user_cap = 0 OR user_cap > 12
                OR (num_rosters - num_generated < user_cap
                    AND NOT EXISTS (SELECT 1 FROM rosters WHERE contest_id = contests.id AND rosters.owner_id=#{self.owner_id})))
            AND NOT private", contest_type.id).order('id asc').first
          if set_contest.nil?
            if contest_type.limit.nil? || Contest.where(contest_type_id: contest_type.id).count < contest_type.limit
              set_contest = Contest.create!(owner_id: 0, buy_in: contest_type.buy_in, user_cap: contest_type.max_entries,
                  market_id: self.market_id, contest_type_id: contest_type.id)
            else
              raise HttpException.new(403, "Contest is full")
            end
          end
        else #contest not nil. enter private contest
          if set_contest.league_id && LeagueMembership.where(:user_id => self.owner_id, :league_id => set_contest.league_id).first.nil?
            LeagueMembership.create!(:league_id => set_contest.league_id, :user_id => self.owner_id)
          end
        end
        set_contest.num_generated += 1 if self.is_generated?
        set_contest.num_rosters += 1
        set_contest.save!
        if set_contest.num_rosters > set_contest.user_cap && set_contest.user_cap != 0
          removed_roster = set_contest.rosters.where('is_generated = true AND NOT cancelled').first
          raise HttpException.new(403, "Contest #{set_contest.id} is full") if removed_roster.nil?
          removed_roster.cancel!("Removed for a real player")
          set_contest.num_rosters -= 1
          set_contest.num_generated -= 1
          set_contest.save!
        end
        self.contest = set_contest
        self.save!

        #charge account
        if contest_type.buy_in > 0 && charge
          self.owner.charge(:monthly_entry, 1, :event => 'buy_in', :roster_id => self.id, :contest_id => self.contest_id)
          #SYSTEM_USER.payout(:monthly_entry, 1, :event => 'rake', :roster_id => nil, :contest_id => self.id) unless self.owner.id == SYSTEM_USER.id
        end
      end

    return self
  end

  def add_player(player, place_bets = true)
    begin
      raise HttpException.new(409, "There is no room for another #{player.position} in your roster") unless remaining_positions.include?(player.position)
      if place_bets
        order = exec_price("SELECT * from buy(#{self.id}, #{player.id})")
        self.class.uncached do
          self.players.reload
          self.rosters_players.reload
        end
        order
      else
        RostersPlayer.create!(:player_id => player.id, :roster_id => self.id, :market_id => self.market_id, :purchase_price => player.buy_price, :player_stats_id => player.stats_id)
        raise "Players passed into add_player without placing bets must have buy_price" if player.buy_price.nil?
        self.remaining_salary -= player.buy_price
        self.class.uncached do
          self.players.reload
          self.rosters_players.reload
        end
        self.save!
      end
    rescue StandardError => e
      if e.message =~ /already in roster/
        raise HttpException.new(409, "That player is already in your roster")
      end
      raise e
    end
  end

  def remove_player(player, place_bets = true)
    if place_bets
      order = exec_price("SELECT * from sell(#{self.id}, #{player.id})")
      self.class.uncached do
        self.players.reload
        self.rosters_players.reload
      end
      order
    else
      # This is okay because it's only used for autogen and doesn't affect the market
      rp = RostersPlayer.where(:player_id => player.id, :roster_id => self.id, :market_id => self.market_id).first
      self.remaining_salary += rp.purchase_price
      rp.destroy!
      self.class.uncached do
        self.players.reload
        self.rosters_players.reload
      end
      self.save!
    end
  end

  def exec_price(sql)
    Integer(ActiveRecord::Base.connection.execute(sql).first['_price'])
  end

  def cleanup
  end

  def started_at
    market.started_at
  end

  def live?
    MarketPlayer.players_live?(market_id, rosters_players)
  end

  def next_game_time
    MarketPlayer.next_game_time_for_roster_players(self)
  end


  # THIS IS ONLY USED FOR TESTING
  def fill_randomly
    #find which positions to fill
    self.players.each{|p| self.remove_player(p) }
    positions = self.position_array
    pos_taken = self.players.collect(&:position)
    pos_taken.each do |pos|
      i = positions.index(pos)
      positions.delete_at(i) if not i.nil?
    end
    return if positions.length == 0
    #pick players that fill those positions
    for_sale = self.purchasable_players
    #organize players by position
    for_sale_by_pos = {}
    positions.each { |pos| for_sale_by_pos[pos] = []}
    for_sale.each do |player|
      for_sale_by_pos[player.position] << player if for_sale_by_pos.include?(player.position)
    end
    #sample players from each position and add to roster
    positions.each do |pos|
      players = for_sale_by_pos[pos]
      player = players.sample
      next if player.nil?
      players.delete(player)
      add_player(player, false)
    end
    self.reload
  end

  def fill_pseudo_randomly3(place_bets = true)
    @candidate_players, indexes = fill_candidate_players
    return self unless @candidate_players
    ActiveRecord::Base.transaction do
      expected = 1.0 * self.contest_type.salary_cap / position_array.length
      begin
        position = remaining_positions.sample # One level of randomization
        players = @candidate_players[position]
        if self.reload.remaining_salary < expected * remaining_positions.length
          slice_start = [players.index{|p| p.buy_price < expected}, 0].compact.max
          slice_end = [indexes[position], slice_start + 3].max
        else
          slice_start = 0
          slice_end = [[players.index{|p| p.buy_price < expected}, indexes[position]].compact.min, 3].max
        end
        player = players.slice(slice_start, slice_end - slice_start).sample
        add_player(player, place_bets)
        @candidate_players[position] = @candidate_players[position].reject{|p| p.id == player.id}
      end while(remaining_positions.length > 0)
    end
    self.reload
  end

  def fill_pseudo_randomly4(place_bets)
    @candidate_players, indexes = fill_candidate_players
    return self unless @candidate_players
    ActiveRecord::Base.transaction do
      begin
        expected = 1.0 * (self.remaining_salary + 5000) / remaining_positions.length
        position = remaining_positions.sample # One level of randomization
        players = @candidate_players[position].slice(0, indexes[position]).each_cons(2).select do |pair|
          pair[0].buy_price >= expected && pair[1].buy_price <= expected
        end.first
        player = if players
          p = (expected - players[0].buy_price).abs < (expected - players[1].buy_price).abs ? players[0] : players[1]
          indexes[position] -= 1 if p
          p
        elsif expected < 0
          indexes[position] -= 1 if indexes[position] > 0
          @candidate_players[position][indexes[position]-1]
        else
          @candidate_players[position].first
        end
        add_player(player, place_bets)
        @candidate_players[position] = @candidate_players[position].reject{|p| p.id == player.id}
      end while(remaining_positions.length > 0)
    end
    self.reload
  end

  def fill_pseudo_randomly6(place_bets = true)
    @candidate_players, indexes = fill_candidate_players
    return self unless @candidate_players
    ActiveRecord::Base.transaction do
      begin
        position = remaining_positions.sample # One level of randomization
        skipped = false
        min = self.reload.remaining_salary - remaining_positions.reduce(0) do |sum, pos| 
          if pos == position && !skipped
            skipped = true
            sum += 0
          else
            sum += @candidate_players[pos][[2, indexes[pos]-1].min].buy_price
          end
        end
        skipped = false
        max = self.remaining_salary - remaining_positions.reduce(0) do |sum, pos| 
          if pos == position && !skipped
            skipped = true
            sum += 0
          else
            sum += @candidate_players[pos][indexes[pos]-1].buy_price
          end
        end
        players = @candidate_players[position].slice(0, indexes[position])
        players = @candidate_players[position] if players.empty?
        if min == max # only one selection left
          min -= 3000
          max += 3000
        end
        eligible_players = players.select{|p| (min..max).include?(p.buy_price)}
        player = if eligible_players.length > 0
          eligible_players.sample
        else
          players.slice(0, [3, indexes[position]].max).sample || players.slice(0, 3).sample
        end
        add_player(player, place_bets)
        @candidate_players[position] = @candidate_players[position].reject{|p| p.id == player.id }
      end while(remaining_positions.length > 0)
    end
    self.reload
  end

  def fill_pseudo_randomly7(place_bets = true)
    fill_pseudo_randomly6(place_bets)
    max_diff = 4000
    @rosters ||= []
    if self.reload.remaining_salary.abs > max_diff
      tries = 5
      begin
        players = self.rosters_players.reload
        @rosters << {players: players, remaining: self.remaining_salary}
        players.sample(2).each{|rp| remove_player(rp.player, false) }
        fill_pseudo_randomly4(place_bets)
        tries -= 1
      end while(self.reload.remaining_salary.abs > max_diff && tries > 0)
      if self.remaining_salary.abs > max_diff
        self.rosters_players.reload.each{|rp| remove_player(rp.player, false) }
        self.purchasable_players.active.where(:id => @rosters.sort_by{|t| t[:remaining].abs }.first[:players].map(&:player_id)).each do |p|
          add_player(p, false)
        end
      end
    end
    self
  end

  def fill_pseudo_randomly5(place_bets = true)
    fill_pseudo_randomly3(place_bets)
    max_diff = 4000
    @rosters ||= []
    if self.reload.remaining_salary.abs > max_diff
      tries = 5
      begin
        players = self.rosters_players.with_market_players(self.market).reload.sort{|rp| -rp.purchase_price }
        @rosters << {players: players, remaining: self.remaining_salary}
        players.select{|rp| !rp.locked }.sample(2).each{|rp| remove_player(rp.player, false) }
=begin
        if self.remaining_salary > 0
          players.slice(0, 2).each{|rp| remove_player(rp.player, false) }
        else
          players.slice(7, 2).each{|rp| remove_player(rp.player, false) }
        end
=end
        fill_pseudo_randomly4(place_bets)
        tries -= 1
      end while(self.reload.remaining_salary.abs > max_diff && tries > 0)
      if self.remaining_salary.abs > max_diff
        self.rosters_players.reload.each{|rp| remove_player(rp.player, false) }
        self.purchasable_players.active.where(:id => @rosters.sort_by{|t| t[:remaining].abs }.first[:players].map(&:player_id)).each do |p|
          add_player(p, false)
        end
      end
    end
    self
  end

=begin
  all players not benched
  low end - high end
  1st pick is random

  all highest priced players for each position

  remaining picks * lowest prices
  
  3rd highest of all positions, determine if we have to pick from that group by establishing minimum price per players

=end

  def weighted_expected_sample(players, expected_salary)
    weighted_sample(players.map do |p|
      p.buy_price = p.buy_price / (p.buy_price - expected_salary).abs
      p
    end)
  end

  def fill_candidate_players
      candidate_players = {}
      indexes = {}
      position_array.each { |pos| candidate_players[pos] = []; indexes[pos] = 0 }
      self.purchasable_players.active.each do |p|
        next unless candidate_players.include?(p.position)
        candidate_players[p.position] << p
        indexes[p.position] += 1 if p.buy_price > 1500
      end
      candidate_players.each do |pos,players|
        candidate_players[pos] = players.sort_by{|player| -player.buy_price }
      end
      return false if candidate_players.map{|pos, players| players.length }.sum <= 9
      [candidate_players, indexes]
  end

  def fill_pseudo_randomly
    @candidate_players, indexes = fill_candidate_players
    return false unless @candidate_players
    ActiveRecord::Base.transaction do
      begin
        position = remaining_positions.sample # One level of randomization
        player = weighted_sample(indexes[position] > 0 ? @candidate_players[position].slice(0, indexes[position]) : @candidate_players[position])
        add_player(player, false)
        @candidate_players[position] = @candidate_players[position].reject{|p| p.id == player.id}
      end while(remaining_positions.length > 0)
    end
    self.reload
  end

  def weighted_sample(players)
    total = players.reduce(0){|sum, p| sum += p.buy_price }
    value = rand
    sum = 0.0
    players.each do |p|
      sum += p.buy_price
      if sum / total > value
        return p
      end
    end
  end

  def position_array
    @position_list ||= self.contest_type.positions.split(',')
  end

  def remaining_positions
    positions = position_array.dup
    pos_taken = self.class.uncached{ self.players.reload }.map(&:position)
    pos_taken.each do |pos|
      i = positions.index(pos)
      positions.delete_at(i) if not i.nil?
    end
    positions
  end

  def pre_destroy
    Roster.find_by_sql("select * from cancel_roster(#{self.id})")
  end

  def cancel!(reason)
    self.with_lock do
      if self.state == 'submitted'
        Roster.transaction do
          self.owner.payout(:monthly_entry, 1, :event => 'cancelled_roster', :roster_id => self.id, :contest_id => self.contest_id)
          self.state = 'cancelled'
          self.cancelled = true
          self.cancelled_at = Time.new
          self.cancelled_cause = reason
          self.save!
          if self.contest
            self.contest.num_rosters -= 1
            self.contest.save!
          end
        end
      end
    end
  end

  def add_bonus(type)
    bonuses = if USER_BONUSES[type]
      bonuses = JSON.parse(self.owner.bonuses || '{}')
      if bonuses[type].nil?
        bonuses[type] = USER_BONUSES[type]
        self.owner.bonuses = bonuses.to_json
        self.bonus_points ||= 0
        self.bonus_points += USER_BONUSES[type]
        self.owner.save!
        self.save!
      end
    elsif ROSTER_BONUSES[type]
      bonuses = JSON.parse(self.bonuses || '{}')
      if bonuses[type].nil?
        bonuses[type] = ROSTER_BONUSES[type]
        self.bonuses = bonuses.to_json
        self.bonus_points ||= 0
        self.bonus_points += ROSTER_BONUSES[type]
        self.save!
      end
    end
  end

end
