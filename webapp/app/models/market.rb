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
          puts "Exception raised for method #{method} on market #{market.id}: #{e}\n#{e.backtrace.slice(0..5).pretty_inspect}..."
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
      self.contests.where("private AND num_rosters < user_cap").find_each do |contest|
        contest.rosters.find_each do |roster|
          roster.contest_id, roster.cancelled_cause, roster.state = nil, 'private contest under-subscribed', 'in_progress'
          roster.save!
          roster.submit!(false)
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
      name: '5k',
      description: '5k Lollapalooza! $2500 for 1st prize!',
      max_entries: 0,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[250000, 100000, 50000, 25000, 15000, 10000, 5000, 5000, 5000, 5000, 2500, 2500,  2500, 2500, 2500, 2500]',
      payout_description: "1st: $2.5k, 2nd: 1k, 3rd: $500, 4th: $250, 5th: $150, 6th: $100, 7th-10th: $50, 10th-16th: $25",
      takes_tokens: false,
    },
=begin
    {
      name: '10k',
      description: '10k Lollapalooza! 5000 to 1 payout for 1st prize!',
      max_entries: 0,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[500000, 200000, 100000, 50000, 30000, 20000, 10000, 10000, 10000, 10000, 5000, 5000,  5000, 5000, 5000, 5000]',
      payout_description: "1st: $5k, 2nd: 2k, 3rd: 1k, 4th: $500, 5th: $300, 6th: $200, 7th-10th: $100, 10th-16th: $50",
      takes_tokens: false,
    },
=end
    {
      name: '970',
      description: '100FF contest, winner gets 970 FanFrees!',
      max_entries: 10,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[970]',
      payout_description: "970ff prize purse, winner takes all",
      takes_tokens: true,
    },
    {
      name: '970',
      description: '10 teams, $1 entry fee, winner takes home $9.70',
      max_entries: 10,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[970]',
      payout_description: "$9.70 prize purse, winner takes all",
      takes_tokens: false,
    },
    {
      name: '970',
      description: '10 teams, $10 entry fee, winner takes home $97.00',
      max_entries: 10,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[9700]',
      payout_description: "$97 prize purse, winner takes all",
      takes_tokens: false,
    },
    {
      name: '194',
      description: '100FF contest, top 5 winners get 194 FanFrees!',
      max_entries: 10,
      buy_in: 100, #100 ff
      rake: 0.03,
      payout_structure: '[194,194,194,194,194]',
      payout_description: "Top five win 194 FanFrees",
      takes_tokens: true,
    },
    {
      name: '194',
      description: '10 teams, $1 entry fee, top 5 winners take home $1.94',
      max_entries: 10,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[194,194,194,194,194]',
      payout_description: "Top five win $1.94",
      takes_tokens: false,
    },
    {
      name: '194',
      description: '10 teams, $10 entry fee, top 5 winners take home $19.40',
      max_entries: 10,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[1940,1940,1940,1940,1940]',
      payout_description: "Top five win $19.40",
      takes_tokens: false,
    },
    {
      name: 'h2h',
      description: '100FF h2h contest, winner gets 194 FanFrees!',
      max_entries: 2,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[194]',
      payout_description: "194ff prize purse, winner takes all",
      takes_tokens: true,
    },
    {
      name: 'h2h',
      description: 'h2h contest, $1 entry fee, winner takes home $1.94',
      max_entries: 2,
      buy_in: 100,
      rake: 0.03,
      payout_structure: '[194]',
      payout_description: "$1.94 prize purse, winner takes all",
      takes_tokens: false,
    },
    {
      name: 'h2h',
      description: 'h2h contest, $10 entry fee, winner takes home $19.40',
      max_entries: 2,
      buy_in: 1000,
      rake: 0.03,
      payout_structure: '[1940]',
      payout_description: "$19.40 prize purse, winner takes all",
      takes_tokens: false,
    },
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, 900FF entry fee, 9 games for 194 per win',
      max_entries: 10,
      buy_in: 900,
      rake: 0.03,
      payout_structure: '[1746, 1552, 1358, 1164, 970, 776, 582, 388, 194]',
      payout_description: "9 h2h games each pay out 194",
      takes_tokens: true,
    },
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, $9 entry fee, 9 games for $1.94 per win',
      max_entries: 10,
      buy_in: 900,
      rake: 0.03,
      payout_structure: '[1746, 1552, 1358, 1164, 970, 776, 582, 388, 194]',
      payout_description: "9 h2h games each pay out $1.94",
      takes_tokens: false,
    },
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, $90 entry fee, 9 games for $19.40 per win',
      max_entries: 10,
      buy_in: 9000,
      rake: 0.03,
      payout_structure: '[17460, 15520, 13580, 11640, 9700, 7760, 5820, 3880, 1940]',
      payout_description: "9 h2h games each pay out $19.40",
      takes_tokens: false,
    }
  ];

  #TODO: is this safe if run concurrently?
  def add_default_contests
    self.transaction do
      return if self.contest_types.length > 0
      @@default_contest_types.each do |data|
      #debugger
        next if data[:name].match(/\d+k/) && self.closed_at - self.started_at < 1.day
        ContestType.create!(
          market_id: self.id,
          name: data[:name],
          description: data[:description],
          max_entries: data[:max_entries],
          buy_in: data[:buy_in],
          rake: data[:rake],
          payout_structure: data[:payout_structure],
          salary_cap: 100000,
          payout_description: data[:payout_description],
          takes_tokens: data[:takes_tokens]
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

  def dump_players_csv
    csv = CSV.generate({}) do |csv|
      csv << ["INSTRUCTIONS: Do not modify the first 4 columns of this sheet.  Fill out the Desired Shadow Bets column. Save the file as a .csv and send back to us"]
      csv << ["Canonical Id", "Name", "Team", "Position", "Desired Shadow Bets"]
      self.players.each do |player|
        csv << [player.stats_id, player.name, player.team.abbrev, player.position]
      end
    end
  end

  def import_players_csv(data)
    self.state = nil
    self.save!
    self.publish

    count = 0
    total_bets = 0
    CSV.parse(data) do |row|
      count += 1
      next if count <= 2
      player_stats_id, shadow_bets = row[0], row[4]
      if !shadow_bets.blank?
        p = Player.where(:stats_id => player_stats_id).first
        if p.nil?
          puts "ERROR: NO PLAYER WITH STATS_ID #{player_stats_id} FOUND"
          next
        end
        puts "betting $#{shadow_bets} on #{p.name}"
        shadow_bets = Integer(shadow_bets) * 100
      else
        shadow_bets = 0
      end
      mp = self.market_players.where("player_stats_id = '#{player_stats_id}'").first
      if mp.nil?
        puts "WARNING: No market player found with id #{player_stats_id}"
        next
      end
      mp.shadow_bets = mp.initial_shadow_bets = mp.bets = shadow_bets
      mp.save!
      total_bets += shadow_bets
    end

    #set the shadow bets to whatever they should be
    puts "\nTotal bets: $#{total_bets/100}"
    self.shadow_bets = self.total_bets = self.initial_shadow_bets = total_bets
    #TEMPORARY: artificially raise the price multiplier
    #self.price_multiplier = self.market_players.size / 50
    puts "using price multiplier: #{self.price_multiplier}"
    self.save!

  end

end
