class Roster < ActiveRecord::Base
  has_and_belongs_to_many :players, -> { select(Player.with_purchase_price.select_values) }, join_table: 'rosters_players', foreign_key: "roster_id"

  has_many :rosters_players
  belongs_to :market
  belongs_to :contest
  belongs_to :contest_type
  belongs_to :owner, class_name: "User", foreign_key: :owner_id
  has_many :market_orders

  validates :state, :inclusion => {in: %w( in_progress canceled submitted finished) }

  validates :owner_id, :market_id, :buy_in, :remaining_salary, :contest_type_id, :state, presence: true

  before_destroy :cleanup

  scope :active, -> { where(state: ['in_progress', 'submitted'])}

  def purchasable_players
    Player.purchasable_for_roster(self)
  end

  def sellable_players
    Player.sellable_for_roster(self)
  end

  #create a roster
  def self.generate(user, contest_type)

    raise HttpException.new(409, "You may only have one roster in progress at a time.") if user.in_progress_roster
    raise HttpException.new(403, "This market is closed") unless contest_type.market.accepting_rosters?
    raise HttpException.new(402, "Insufficient funds") unless user.can_charge?(contest_type.buy_in)

    roster = nil
    self.transaction do
      roster = Roster.create!(
        :owner_id => user.id,
        :market_id => contest_type.market_id,
        :contest_type_id => contest_type.id,
        :buy_in => contest_type.buy_in,
        :remaining_salary => 100000,
        :state => 'in_progress',
        :positions => Positions.for_sport_id(contest_type.market.sport_id),
      )
      user.customer_object.decrease_balance(contest_type.buy_in, 'buy_in', roster.id) if contest_type.buy_in > 0
    end
    roster
  end

  def build_from_existing(roster)
    roster.players.each do |player|
      self.add_player(player)
    end
  end

  #set the state to 'submitted'. If it's in a private contest, increment the number of 
  #rosters in the private contest. If not, enter it into a public contest, creating a new one if necessary.
  def submit!
    self.with_lock do
      raise "roster has already been submitted" if self.state == 'submitted'
      if self.contest.nil?
        #enter roster into public contest
        contest_type.with_lock do #prevents creation of contests of the same type at the same time
          contest = Contest.where("contest_type_id = ? AND (num_rosters < user_cap OR user_cap = 0) 
            AND invitation_code is null", contest_type.id).first
          if contest.nil?
            contest = Contest.create(owner_id: 0, buy_in: contest_type.buy_in, user_cap: contest_type.max_entries,
              market_id: self.market_id, contest_type_id: contest_type.id, num_rosters: 1)
          else
            contest.num_rosters += 1
            contest.save!
          end
          self.contest = contest
        end
      else
        contest.with_lock do
          raise "contest #{contest.id} is full" if contest.num_rosters >= contest.user_cap
          contest.num_rosters += 1
          contest.save!
        end
      end
      self.state = 'submitted'
      self.submitted_at = Time.now
      self.save!
    end
    return self
  end

  def add_player(player)
    MarketOrder.buy_player(self, player)
  end

  def remove_player(player)
    MarketOrder.sell_player(self, player)
  end

  def cleanup
    players.each{|p| remove_player(p) }
    market_orders.destroy_all
    owner.customer_object.increase_balance(self.buy_in, 'canceled_roster')
  end

  def live?
    MarketPlayer.players_live?(rosters_players)
  end

  def next_game_time
    MarketPlayer.next_game_time_for_players(rosters_players)
  end

  #buys random players to fill up the roster (all empty positions)
  #how randomly? well, that may change, but for now it's pretty random.
  def fill_randomly
    #find which positions to fill
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
      for_sale_by_pos[player.position] << player if for_sale_by_pos.include? player.position
    end
    #sample players from each position and add to roster
    positions.each do |pos|
      players = for_sale_by_pos[pos]
      player = players.sample
      next if player.nil?
      players.delete(player)
      self.add_player(player)
    end
    self.reload 
  end

end
