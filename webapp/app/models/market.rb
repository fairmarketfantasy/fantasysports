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

  class << self

    # THIS IS A UTILITY FUNCTION, DO NOT CALL IT FROM THE APPLICATION
    def load_sql_functions
      self.load_sql_file File.join(Rails.root, '..', 'market', 'market.sql')
    end

    def tend
      publish
      open
      remove_shadow_bets
      lock_players
      close
      tabulate_scores
      complete
    end

    def apply method, sql, *params
      Market.where(sql, *params).each do |market|
        puts "#{Time.now} -- #{method} market #{market.id}"
        begin
          market.send(method)
        rescue Exception => e
          puts "Exception raised for method #{method} on market #{market.id}: #{e}"
        end
      end
    end

    def publish
      apply :publish, "published_at <= ? AND (state is null or state='' or state='unpublished')", Time.now
    end

    def open
      apply :open, "state = 'published' AND (shadow_bets = 0 or opened_at < ?)", Time.now
    end

    def remove_shadow_bets
      apply :remove_shadow_bets, "state in ('published', 'opened') and shadow_bets > 0"
    end
  
    def lock_players
      apply :lock_players, "state = 'opened'"
    end
    
    def tabulate_scores
      apply :tabulate_scores, "state in ('published', 'opened', 'closed')"
    end

    def close
      apply :close, "state = 'opened' AND closed_at < ?", Time.now
    end

    def complete
      apply :complete, "state = 'closed' and not exists (select 1 from games g join games_markets gm on gm.game_stats_id = g.stats_id where gm.market_id = markets.id and g.status != 'closed')"
    end

  end

  def accepting_rosters?
    ['published', 'opened'].include?(self.state)
  end

  #publish the market. returns the published market.
  def publish
    Market.find_by_sql("select * from publish_market(#{self.id})")
    reload
    if self.state == 'published'
      self.add_default_contests
    end
    self
  end
  
  def open
    Market.find_by_sql("select * from open_market(#{self.id})")
    reload
  end

  def remove_shadow_bets
    Market.find_by_sql("select * from remove_shadow_bets(#{self.id})")
    reload
  end

  def lock_players
    Market.find_by_sql("SELECT * from lock_players(#{self.id})")
    reload
  end

  def tabulate_scores
    Market.find_by_sql("SELECT * FROM tabulate_scores(#{self.id})")
    reload
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
      self.rosters.where("state != 'submitted'").each {|r| r.cancel!('un-submitted before market closed') }

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
        contest.rosters.each{|r| r.cancel!('contest under-subscribed') }
        contest.destroy!
      end

      self.state, self.closed_at = 'closed', Time.now
      save!
    end
    return self
  end


  #if a market is closed and all its games are over, then 'complete' the market
  #by dishing out funds and such
  def complete
    #make sure all games are closed
    self.with_lock do
      raise "market must be closed before it can be completed" if self.state != 'closed'
      raise "all games must be closed before market can be completed" if self.games.where("status != 'closed'").any?

      self.tabulate_scores
      #for each contest, allocate funds by rank
      self.contests.find_each do |contest|
        contest.payday!
      end
      self.state = 'complete'
      self.save!
    end
  end

  @@default_contest_types = [
    # Name, description,                                              max_entries, buy_in, rake, payout_structure
    {
      name: '100k',
      description: '100k Lollapalooza! 5000 to 1 payout for 1st prize!',
      max_entries: 0,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[5000000, 2500000, 1200000, 600000, 300000, 200000, 100000, 48500, 48500]',
      payout_description: "Winner takes half, top 9 slots win big."
    },
    {
      name: '970',
      description: 'Free contest, winner gets 10 FanFrees!',
      max_entries: 10,
      buy_in: 0,
      rake: 0.03,
      payout_structure: '[]',
      payout_description: "Winner takes all",
    },
    {
      name: '970',
      description: '10 teams, $1 entry fee, winner takes home $9.70',
      max_entries: 10,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[970]',
      payout_description: "Winner takes all",
    },
    {
      name: '970',
      description: '10 teams, $10 entry fee, winner takes home $97.00',
      max_entries: 10,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[9700]',
      payout_description: "Winner takes all",
    },
    {
      name: '194',
      description: 'Free contest, top 5 winners get 194 FanFrees!',
      max_entries: 10,
      buy_in: 0, #100 ff
      rake: 0.03,
      payout_structure: '[]',
      payout_description: "Top half wins",
    },
    {
      name: '194',
      description: '10 teams, $1 entry fee, top 5 winners take home $1.94',
      max_entries: 10,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[194,194,194,194,194]',
      payout_description: "Top half wins",
    },
    {
      name: '194',
      description: '10 teams, $10 entry fee, top 5 winners take home $19.40',
      max_entries: 10,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[1940,1940,1940,1940,1940]',
      payout_description: "Top half wins",
    },
    {
      name: 'h2h',
      description: 'Free h2h contest, winner gets 1 FanFree!',
      max_entries: 2,
      buy_in: 0,
      rake: 0.03,
      payout_structure: '[]',
      payout_description: "Winner takes all",
    },
    {
      name: 'h2h',
      description: 'h2h contest, $1 entry fee, winner takes home $1.94',
      max_entries: 2,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[194]',
      payout_description: "Winner takes all",
    },
    {
      name: 'h2h',
      description: 'h2h contest, $10 entry fee, winner takes home $19.40',
      max_entries: 2,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[1940]',
      payout_description: "Winner takes all",
    },
    {
      name: 'h2h rr',
      description: 'Free 10 team, h2h round-robin contest, 900 entry fee, 9 games for 194 per win',
      max_entries: 10,
      buy_in: 0,
      rake: 0.03,
      payout_structure: '[]',
      payout_description: "9 h2h games for $1.94 each",
    },
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, $9 entry fee, 9 games for $1.94 per win',
      max_entries: 10,
      buy_in: 900,
      rake: 0.03,
      payout_structure: '[1746, 1552, 1358, 1164, 970, 776, 582, 388, 194]',
      payout_description: "9 h2h games for $1.94 each",
    },
    {
      name: 'h2h rr',
      description: 'Free 10 team, h2h round-robin contest, $90 entry fee, 9 games for $19.40 per win',
      max_entries: 10,
      buy_in: 9000,
      rake: 0.03,
      payout_structure: '[17460, 15520, 13580, 11640, 9700, 7760, 5820, 3880, 1940]',
      payout_description: "9 h2h games for $19.40 each",
    }
  ];

  #TODO: is this safe if run concurrently?
  def add_default_contests
    self.transaction do
      return if self.contest_types.length > 0
      @@default_contest_types.each do |data|
        pp data
      ContestType.create!(
        market_id: self.id,
        name: data[:name],
        description: data[:description],
        max_entries: data[:max_entries],
        buy_in: data[:buy_in],
        rake: data[:rake],
        payout_structure: data[:payout_structure],
        salary_cap: 100000,
        payout_description: data[:payout_description]
        )
      end
    end
    self.contest_types.reload
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
    raise "could not find system user" if system_user.nil?
    num_rosters.times { Roster.generate(system_user, contest_type).fill_randomly.submit! }
  end

end
