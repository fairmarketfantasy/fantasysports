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

    if user.in_progress_roster
      raise HttpException.new(409, "You may only have one roster in progress at a time.")
    end

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
      user.customer_object.decrease_balance(contest_type.buy_in, 'buy_in', roster.id)
    end
    roster
  end

  def build_from_existing(roster)
    roster.players.each do |player|
      self.add_player(player)
    end
  end

  def submit!
    self.state = 'submitted'
    self.submitted_at = Time.now
    self.save!
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

  require 'set'

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
