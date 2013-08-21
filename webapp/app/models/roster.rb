class Roster < ActiveRecord::Base
  has_and_belongs_to_many :players, join_table: 'rosters_players', foreign_key: "contest_roster_id"
  belongs_to :contest
  belongs_to :owner, class_name: "User", foreign_key: :owner_id

  validates :state, :inclusion => {in: %w( in_progress cancelled submitted ) }

  validates :owner_id, :market_id, :buy_in, :remaining_salary, :contest_type, :state, presence: true

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
      :contest_type => contest_type,
      :buy_in => buy_in,
      :remaining_salary => 100000,
      :state => 'in_progress',
      :positions => Positions.for_sport_id(market.sport_id),
    )
  end

  def add_player(player)
      MarketOrder.buy_player(self, player)
  end

  def remove_player(player)
      MarketOrder.sell_player(self, player)
  end

  protected


end
