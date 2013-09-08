class Market < ActiveRecord::Base
  has_many :games_markets, :inverse_of => :market
  has_many :games, :through => :games_markets
  has_many :market_players
  has_many :players, :through => :market_players
  has_many :contests
  has_many :contest_types
  belongs_to :sport

  validates :shadow_bets, :shadow_bet_rate, :sport_id, presence: true

  scope :published_after,   ->(time) { where('published_at > ?', time)}
  scope :opened_after,      ->(time) { where("opened_at > ?", time) }
  scope :closed_after,      ->(time) { where('closed_at > ?', time) }

  paginates_per 25

  def accepting_rosters?
    ['published', 'opened'].include?(self.state)
  end

  #publish the market. returns the published market.
  def publish
    raise "market cannot be published: state=#{self.state}" if ![nil, ''].include?(self.state)
    cur_state = self.state
    Market.find_by_sql("select * from publish_market(#{self.id})")[0]
    self.reload
    if self.state == 'published' && self.contest_types.length == 0
      add_default_contests
    end
    reload
  end

  def open
    Market.find_by_sql("select * from open_market(#{self.id})")[0]
    reload
  end

  def close
    Market.find_by_sql("select * from close_market(#{self.id})")[0]
    reload
  end

  #look for players in games that have started and remove them from the market
  #and update the price multiplier
  def lock_players
    Market.find_by_sql("SELECT * from lock_players(#{self.id})")[0]
  end

  @@default_contest_types = [
    ['100k', '100k lalapalooza!', 0, 10, 0.03, '[50000, 25000, 12000, 6000, 3000, 2000, 1000, 500, 500]'],
    ['970', 'Free contest, winner gets 10 FanFrees!', 10, 0, 0, '[F10]'],
    ['970', '10 teams, $2 entry fee, winner takes home $19.40', 10, 2, 0.03, '[19.40]'],
    ['970', '10 teams, $10 entrye fee, winner takes home $97.00', 10, 10, 0.03, '[97]'],
    ['194', 'Free contest, top 25 winners get 2 FanFrees!', 50, 0, 0, '[F2]'],
    ['194', '50 teams, $2 entry fee, top 25 winners take home $3.88', 50, 2, 0.03, '{0-24: 3.88}'],
    ['194', '50 teams, $10 entrye fee, top 25 winners take home $19.40', 50, 10, 0.03, '{0-24: 19.40}'],
    ['h2h', 'Free h2h contest, winner gets 1 FanFree!', 2, 0, 0, '[F1]'],
    ['h2h', 'h2h contest, $2 entry fee, winner takes home $3.88', 2, 2, 0.03, '[3.88]'],
    ['h2h', 'h2h contest, $10 entry fee, winner takes home $19.40', 2, 10, 0.03, '[19.40]']
  ];

  #TODO: is this safe if run concurrently?
  def add_default_contests
    self.contest_types.reload.transaction do
      return if self.contest_types.length > 0
      @@default_contest_types.each do |data|
      ContestType.create(
        market_id: self.id,
        name: data[0],
        description: data[1],
        max_entries: data[2],
        buy_in: data[3],
        rake: data[4],
        payout_structure: data[5]
        )
      end
    end
  end

end
