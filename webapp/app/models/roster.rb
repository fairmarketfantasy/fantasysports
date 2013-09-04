class Roster < ActiveRecord::Base
  has_and_belongs_to_many :players, -> { select(Player.with_purchase_price.select_values) }, join_table: 'rosters_players', foreign_key: "roster_id"

  has_many :rosters_players, :dependent => :destroy
  belongs_to :market
  belongs_to :contest
  belongs_to :contest_type
  belongs_to :owner, class_name: "User", foreign_key: :owner_id
  has_many :market_orders

  validates :state, :inclusion => {in: %w( in_progress cancelled submitted ) }

  validates :owner_id, :market_id, :buy_in, :remaining_salary, :contest_type_id, :state, presence: true

  before_destroy :cleanup_players

  def players_with_prices
    Player.with_sell_price.joins("join sell_prices(#{self.id}) as sell_prices on sell_prices.player_id = players.id")
  end

  def self.generate_contest_roster(user, market, contest_type, buy_in)
    if !Contest.valid_contest?(contest_type, buy_in)
      raise HttpException.new(400, "Invalid contest type/buy in")
    end

    if user.in_progress_roster
      raise HttpException.new(409, "You may only have one roster in progress at a time.")
    end

    r = Roster.create!(
      :owner => user,
      :market_id => market.id,
      :contest_type_id => contest_type_id,
      :buy_in => buy_in,
      :remaining_salary => 100000,
      :state => 'in_progress',
      :positions => Positions.for_sport_id(market.sport_id),
    )
  end

  #create a roster
  def self.generate(user, contest_type)

    if user.in_progress_roster
      raise HttpException.new(409, "You may only have one roster in progress at a time.")
    end

    r = Roster.create!(
      :owner_id => user.id,
      :market_id => contest_type.market_id,
      :contest_type_id => contest_type.id,
      :buy_in => contest_type.buy_in,
      :remaining_salary => 100000,
      :state => 'in_progress',
      :positions => Positions.for_sport_id(contest_type.market.sport_id),
    )
  end

  def submit!
    owner = self.owner
    raise HttpException.new(402, "Insufficient funds") unless owner.can_charge?(self.buy_in)
    self.transaction do
      owner.customer_object.decrease_balance(roster.buy_in, 'buy_in', self.id)
      self.state = 'submitted'
      self.submitted_at = Time.now
      self.save!
    end
  end

  def add_player(player)
    MarketOrder.buy_player(self, player)
  end

  def remove_player(player)
    MarketOrder.sell_player(self, player)
  end

  def cleanup_players
    players.each{|p| remove_player(p) }
  end

end
