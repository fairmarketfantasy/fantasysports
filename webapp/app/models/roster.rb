
class Roster < ActiveRecord::Base
  attr_protected

  has_and_belongs_to_many :players, -> { select(Player.with_purchase_price.select_values) }, join_table: 'rosters_players'
  has_many :rosters_players
  belongs_to :market
  belongs_to :contest
  belongs_to :contest_type
  belongs_to :owner, class_name: "User", foreign_key: :owner_id
  has_many :market_orders

  validates :state, :inclusion => {in: %w( in_progress cancelled submitted finished) }

  validates :owner_id, :market_id, :buy_in, :remaining_salary, :contest_type_id, :state, presence: true

  before_destroy :pre_destroy

  scope :over, -> { where(state: ['cancelled', 'finished'])}
  scope :active, -> { where(state: ['in_progress', 'submitted'])}
  scope :submitted, -> { where(state: ['submitted'])}
  scope :finished, -> { where(state: ['finished'])}

  def players_with_prices
    self.class.uncached do
      Player.find_by_sql("select * from roster_prices(#{self.id})")
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
      :positions => Positions.for_sport_id(contest_type.market.sport_id),
    )
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

  def submit_without_sql_func
    raise HttpException.new(402, "Insufficient #{contest_type.takes_tokens? ? 'tokens' : 'funds'}") if charge && !owner.can_charge?(contest_type.buy_in, contest_type.takes_tokens?)
    self.transaction do
      set_contest = contest
      #enter contest
      contest_type.with_lock do #prevents creation of contests of the same type at the same time
        if set_contest.nil?
          #enter roster into public contest
          set_contest = Contest.where("contest_type_id = ?
            AND (user_cap = 0 OR user_cap > 10
                OR (num_rosters - num_generated < user_cap
                    AND NOT EXISTS (SELECT 1 FROM rosters WHERE contest_id = contests.id AND rosters.owner_id=#{self.owner_id})))
            AND NOT private", contest_type.id).order('id asc').first
          if set_contest.nil?
            if contest_type.limit.nil? || Contest.where(contest_type_id: contest_type.id).count < contest_type.limit
              set_contest = Contest.create(owner_id: 0, buy_in: contest_type.buy_in, user_cap: contest_type.max_entries,
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
      end

      #charge account
      if contest_type.buy_in > 0 && charge
        self.owner.charge(self.contest_type.buy_in, self.contest_type.takes_tokens, :event => 'buy_in', :roster_id => self.id, :contest_id => self.contest_id)
      end

    end
    return self
  end

  #set the state to 'submitted'. If it's in a private contest, increment the number of 
  #rosters in the private contest. If not, enter it into a public contest, creating a new one if necessary.
  def submit!(charge = true)
    #buy all the players on the roster. This sql function handles all of that.
    raise HttpException.new(402, "Insufficient #{contest_type.takes_tokens? ? 'tokens' : 'funds'}") if charge && !owner.can_charge?(contest_type.buy_in, contest_type.takes_tokens?)
    self.transaction do
      #purchase all the players and update roster state to submitted
      Roster.find_by_sql("SELECT * FROM submit_roster(#{self.id})")
      reload

      set_contest = contest
      #enter contest
      contest_type.with_lock do #prevents creation of contests of the same type at the same time
        if set_contest.nil?
          #enter roster into public contest
          set_contest = Contest.where("contest_type_id = ?
            AND (user_cap = 0 OR user_cap > 10
                OR (num_rosters - num_generated < user_cap
                    AND NOT EXISTS (SELECT 1 FROM rosters WHERE contest_id = contests.id AND rosters.owner_id=#{self.owner_id})))
            AND NOT private", contest_type.id).order('id asc').first
          if set_contest.nil?
            if contest_type.limit.nil? || Contest.where(contest_type_id: contest_type.id).count < contest_type.limit
              set_contest = Contest.create(owner_id: 0, buy_in: contest_type.buy_in, user_cap: contest_type.max_entries,
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
      end

      #charge account
      if contest_type.buy_in > 0 && charge
        self.owner.charge(self.contest_type.buy_in, self.contest_type.takes_tokens, :event => 'buy_in', :roster_id => self.id, :contest_id => self.contest_id)
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
        self.rosters_players << RostersPlayer.new(:player_id => player.id, :roster_id => self.id, :market_id => self.market_id, :purchase_price => player.buy_price, :player_stats_id => player.stats_id)
        raise "Players passed into add_player without placing bets must have buy_price" if player.buy_price.nil?
        self.remaining_salary -= player.buy_price
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
    MarketPlayer.next_game_time_for_players(self)
  end


  # THIS IS ONLY USED FOR TESTING
  def fill_randomly
    #find which positions to fill
    self.players.each{|p| self.remove_player(p) }
    positions = self.positions.split(',') #TODO- could cache this
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

  def fill_pseudo_randomly3(extend_ratio = 0.8)
    @candidate_players, indexes = fill_candidate_players
    return self unless @candidate_players
    ActiveRecord::Base.transaction do
      expected = 1.0 * self.reload.remaining_salary / remaining_positions.length
      begin
        position = remaining_positions.sample # One level of randomization
        players = @candidate_players[position]
        if self.reload.remaining_salary < expected * remaining_positions.length
          slice_start = [players.index{|p| p.buy_price < expected * extend_ratio}, 0].compact.max
          slice_end = [indexes[position], slice_start + 3].max
        else
          slice_start = 0
          slice_end = [[players.index{|p| p.buy_price < expected * extend_ratio}, indexes[position]].compact.min, 3].max
        end
        player = players.slice(slice_start, slice_end - slice_start).sample
        add_player(player, false)
        @candidate_players[position] = @candidate_players[position].reject{|p| p.id == player.id}
      end while(remaining_positions.length > 0)
    end
    self.reload
  end

  def fill_pseudo_randomly4
    @candidate_players, indexes = fill_candidate_players
    return self unless @candidate_players
    ActiveRecord::Base.transaction do
      begin
        expected = 1.0 * self.reload.remaining_salary / remaining_positions.length
        min = 2000
        max = @candidate_players.inject(0) {|sum, pos_players| sum += pos_players[1][[3, pos_players[1].length - 1].min].buy_price } - min * (remaining_positions.length - 1)
        position = remaining_positions.sample # One level of randomization
        players = @candidate_players[position]
        if self.reload.remaining_salary < expected * remaining_positions.length
            slice_start = [players.index{|p| p.buy_price < max}, 0].compact.max
            slice_end = [indexes[position], slice_start + 3].max
        else
          if max > self.contest_type.salary_cap - self.remaining_salary
            player = players.first
          else
            slice_start = 0
            slice_end = [[players.index{|p| p.buy_price < expected}, indexes[position]].compact.min, 3].max
          end
        end
        player = player || players.slice(slice_start, slice_end - slice_start).sample
        add_player(player, false)
        @candidate_players[position] = @candidate_players[position].reject{|p| p.id == player.id}
        player = nil
      end while(remaining_positions.length > 0)
    end
    self.reload
  end

  def fill_pseudo_randomly5
    fill_pseudo_randomly3(1.0)
    max_diff = 4000
    if self.reload.remaining_salary.abs > max_diff
      tries = 3
      begin
        players = self.rosters_players.reload.sort{|rp| -rp.purchase_price }
        if self.remaining_salary > max_diff
          players.slice(6, 3).each{|rp| remove_player(rp.player, false) }
        else
          players.slice(0, 3).each{|rp| remove_player(rp.player, false) }
        end
        fill_pseudo_randomly3(1.0)
        tries -= 1
      end while(self.reload.remaining_salary.abs > max_diff && tries > 0)
    end
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
      self.purchasable_players.select{|p| p.status == 'ACT' && p.benched_games < 3}.each do |p|
        candidate_players[p.position] << p if candidate_players.include?(p.position)
        indexes[p.position] += 1 if p.buy_price > 2000
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
    @position_list ||= self.positions.split(',')
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
          self.owner.payout(self.buy_in, self.contest_type.takes_tokens?, :event => 'cancelled_roster', :roster_id => self.id, :contest_id => self.contest_id)
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

end
