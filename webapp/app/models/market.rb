class Market < ActiveRecord::Base
  has_many :games_markets, :inverse_of => :market
  has_many :games, :through => :games_markets
  has_many :market_players
  has_many :players, :through => :market_players
  has_many :contests
  has_many :contest_types
  has_many :rosters
  belongs_to :sport

  validates :shadow_bets, :shadow_bet_rate, :sport_id, presence: true
  validates :state, inclusion: { in: %w( published opened closed complete ), allow_nil: true }

  scope :published_after,   ->(time) { where('published_at > ?', time)}
  scope :opened_after,      ->(time) { where("opened_at > ?", time) }
  scope :closed_after,      ->(time) { where('closed_at > ?', time) }

  paginates_per 25

  def accepting_rosters?
    ['published', 'opened'].include?(self.state)
  end

  def self.publish_all
	  markets = Market.where("published_at <= ? AND (state is null or state='' or state='unpublished')", Time.now)
	  markets.each do |market|
	  	puts "#{Time.now} -- publishing market #{market.id}"
      market = market.publish
    end
  end

  #publish the market. returns the published market.
  def publish
    Market.find_by_sql("select * from publish_market(#{self.id})")
    reload
    if self.state == 'published'
      self.add_default_contests
    end
    return self
  end
  
  # Opening the market updates shadow bets until they're all removed.  
  # The market will remain in a published state until that happens
  def self.open_all
	  markets = Market.where("state = 'published'")
	  markets.each do |market|
	  	puts "#{Time.now} -- opening market #{market.id}"
      market.open
	  end
  end

  def open
    Market.find_by_sql("select * from open_market(#{self.id})")
    reload
    return self
  end

  #look for players in games that have started and remove them from the market
  #and update the price multiplier
  def self.lock_players_all
    markets = Market.where("state = 'opened' OR state = 'published'")
    markets.each do |market|
      puts "#{Time.now} -- locking players in market #{market.id}"
      market.lock_players
    end
  end

  def lock_players
    Market.find_by_sql("SELECT * from lock_players(#{self.id})")
    return self
  end

  def self.tabulate_all
    Market.where("state in ('published', 'opened', 'closed')").find_each do |market|
      puts "#{Time.now} -- tabulating scores for market #{market.id}"
      market.tabulate_scores
    end
  end

  def tabulate_scores
    Market.find_by_sql("SELECT * FROM tabulate_scores(#{self.id})")
    return self
  end


  def self.close_all
	  markets = Market.where("closed_at <= ? AND state = 'opened'", Time.now)
	  markets.each do |market|
	  	puts "#{Time.now} -- closing market #{market.id}"
      market.close
	  end
  end

  # close a market. allocates remaining rosters in this manner:
  # - cancel rosters that have not yet been submitted
  # - delete private contests that are not full
  # - allocate rosters from private contests to public ones
  # - cancel contests/rosters that are not full
  def close
    self.with_lock do
      raise "cannot close if state is not open" if state != 'opened' 

      #cancel all un-submitted rosters
      self.rosters.where("state != 'submitted'").update_all(["cancelled = true, cancelled_at = ?,
       cancelled_cause='un-submitted before market closed'", Time.now])

      #re-allocate rosters in under-subscribed private contests to public contests
      self.contests.where("invitation_code is not null and num_rosters < user_cap").find_each do |contest|
        contest.rosters.find_each do |roster|
          roster.contest_id, roster.cancelled_cause, roster.state = nil, 'private contest under-subscribed', 'in_progress'
          roster.save!
          roster.submit!
        end
        contest.destroy!
      end

      #cancel rosters in contests that are not full
      self.contests.where("num_rosters < user_cap").find_each do |contest|
        contest.rosters.update_all("contest_id = null, cancelled = true, 
          cancelled_cause = 'contest under-subscribed', cancelled_at = '#{Time.now}'")
        contest.destroy!
      end

      self.state, self.closed_at = 'closed', Time.now
      save!
    end
    return self
  end


  def self.complete_all
    markets = Market.where("state = 'closed'")
    puts "found #{markets.length} markets to potentially complete"
    markets.each do |market|
      puts "#{Time.now} -- completing market #{market.id}"
      begin
        market.complete
      rescue
      end
    end
  end

  #if a market is closed and all its games are over, then 'complete' the market
  #by dishing out funds and such
  def complete
    #make sure all games are closed
    self.with_lock do
      raise "market must be closed before it can be completed" if self.state != 'closed'
      raise "all games must be closed before market can be completed" if self.games.where("status != 'closed'").size > 0

      self.tabulate_scores
      #for each contest, allocate funds by rank
      self.contests.find_each do |contest|
        contest.payday!
      end
      self.state = 'complete'
      self.save!
    end
  end

  def self.tend_all
	  Market.publish_all
	  Market.open_all
    Market.lock_players_all
    Market.close_all
    Market.tabulate_all
    Market.complete_all
  end

  @@default_contest_types = [
    ['100k', '100k lalapalooza!',                                      0, 1000, 0.03, '[5000000, 2500000, 1200000, 600000, 300000, 200000, 100000, 50000, 50000]'],
    ['970', 'Free contest, winner gets 10 FanFrees!',                  10, 0, 0, '[]'],
    ['970', '10 teams, $2 entry fee, winner takes home $19.40',        10, 200, 0.03, '[1940]'],
    ['970', '10 teams, $10 entry fee, winner takes home $97.00',       10, 1000, 0.03, '[9700]'],
    ['194', 'Free contest, top 5 winners get 2 FanFrees!',             10, 0, 0, '[]'],
    ['194', '10 teams, $2 entry fee, top 5 winners take home $3.88',   10, 200, 0.03, '[388, 388, 388, 388, 388]'],
    ['194', '10 teams, $10 entry fee, top 5 winners take home $19.40', 10, 1000, 0.03, '[1940, 1940, 1940, 1940, 1940]'],
    ['h2h', 'Free h2h contest, winner gets 1 FanFree!',                2, 0, 0, '[]'],
    ['h2h', 'h2h contest, $2 entry fee, winner takes home $3.88',      2, 200, 0.03, '[388]'],
    ['h2h', 'h2h contest, $10 entry fee, winner takes home $19.40',    2, 1000, 0.03, '[1940]']
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
    return self
  end

  def reset_for_testing
    self.games.update_all(:game_day => Time.now, :game_time => Time.now + 3600, :status => 'scheduled')
    self.published_at, self.opened_at, self.closed_at, self.state = Time.now, Time.now + 1200, Time.now + 3600, nil
    self.save!
  end

  #if this market has a 100k contest, buys a random roster in the 100k using the system user's account
  def enter_100k(num_rosters=1)
    contest_type = self.contest_types.where("name = '100k'").first
    raise "no 100k contest" if contest_type.nil?
    system_user = User.where(:name => 'SYSTEM USER').first
    raise "could not find system uers" if system_user.nil?
    num_rosters.times { Roster.generate(system_user, contest_type).fill_randomly.submit! }
  end

end
