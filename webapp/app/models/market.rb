require 'data_fetcher'

class Market < ActiveRecord::Base
  attr_protected
  has_many :games_markets, :inverse_of => :market
  has_many :games, :through => :games_markets
  has_many :market_players
  has_many :players, :through => :market_players
  has_many :contests
  has_many :contest_types
  has_many :rosters
  has_many :individual_predictions
  belongs_to :sport
  belongs_to :linked_market, :class_name => 'Market'

  validates :shadow_bets, :shadow_bet_rate, :sport_id, presence: true
  validates :state, inclusion: { in: %w( published opened closed complete ), allow_nil: true }
  validates :game_type, inclusion: { in: %w( regular_season single_elimination team_single_elimination )}

  scope :published_after,   ->(time) { where('published_at > ?', time)}
  scope :opened_after,      ->(time) { where("opened_at > ?", time) }
  scope :closed_after,      ->(time) { where('closed_at > ?', time) }

  before_save :set_game_type

  paginates_per 25

  #@@thread_pool = ThreadPool.new(4)

  class << self

    # THIS IS A UTILITY FUNCTION, DO NOT CALL IT FROM THE APPLICATION
    def load_sql_functions
      self.load_sql_file File.join(Rails.root, '..', 'market', 'session_variables.sql')
      self.load_sql_file File.join(Rails.root, '..', 'market', 'market.sql')
    end

    def tend
      publish
      open
      remove_shadow_bets
      track_benched_players
      fill_rosters
      DataFetcher.update_benched
      remove_benched_players
      close
      lock_players
      tabulate_scores
      set_payouts # this is used for leaderboards
      deliver_bonuses
      finish_games
      remove_duplicated_games!
      complete
    end

    def apply method, sql, *params
      Market.where(sql, *params).order('id asc').each do |market|
        puts "#{Time.now} -- #{method} market #{market.id}"
        #@@thread_pool.schedule do
          begin
=begin
init_shadow_bets = market.reload.initial_shadow_bets
total_bets = market.reload.total_bets
shadow_bets = market.reload.shadow_bets
real_bets = market.reload.total_bets - shadow_bets
new_shadow_bets = [0, market.initial_shadow_bets - real_bets * market.shadow_bet_rate].max
=end
              market.send(method)
          rescue Exception => e
            puts "Exception raised for method #{method} on market #{market.id}: #{e}\n#{e.backtrace.slice(0..5).pretty_inspect}..."
            Rails.logger.error "Exception raised for method #{method} on market #{market.id}: #{e}\n#{e.backtrace.slice(0..5).pretty_inspect}..."
            raise e if Rails.env == 'test'
            #Honeybadger.notify(
            #  :error_class   => "MarketTender Error",
            #  :error_message => "MarketTenderError in #{method} for #{market.id}: #{e.message}",
            #  :backtrace => e.backtrace
            #)
          end
        #end
      end
      #@@thread_pool.wait_for_empty
    end

    def publish
      apply :publish, "published_at <= ? AND (state is null or state='' or state='unpublished')", Time.now
    end

    def remove_duplicated_games!
      Market.where(state: 'closed').each do |m|
        game_ids = m.games_markets.where.not(finished_at: nil).map do |gm|
          game = gm.game
          game.stats_id if game.status == 'closed'
        end

        game_ids.compact.each do |game_id|
          Game.where(stats_id: game_id).each { |game| game.destroy if game.status != 'closed' }
        end
      end
    end

    def open
      apply :open, "state = 'published' AND (shadow_bets = 0 or opened_at < ?)", Time.now
    end

    def remove_shadow_bets
      apply :remove_shadow_bets, "state in ('published', 'opened') and shadow_bets > 0"
    end

    def fill_rosters
      apply :fill_rosters, "state IN('opened')"
    end

    def remove_benched_players
      apply :remove_benched_players, "state IN('opened')"
    end

    def track_benched_players
      apply :track_benched_players, "state IN('opened', 'published')"
    end

    def lock_players
      apply :lock_players, "state IN('opened', 'closed')"
    end

    def tabulate_scores
      apply :tabulate_scores, "state in ('published', 'opened', 'closed')"
    end

    def deliver_bonuses
      apply :deliver_bonuses, "game_type = 'single_elimination' AND state in ('opened', 'closed')"
    end

    def set_payouts
      apply :set_payouts, "state in ('opened', 'closed')"
    end

    def finish_games
      apply :finish_games, "state in ('opened', 'closed')"
    end

    def close
      apply :close, "state = 'opened' AND closed_at < ?", Time.now
    end

    def complete
      apply :complete, <<-EOF
          state = 'closed' AND NOT EXISTS (
            SELECT 1 FROM games g JOIN games_markets gm ON gm.game_stats_id = g.stats_id
             WHERE gm.market_id = markets.id AND (g.status != 'closed' OR gm.finished_at IS NULL))
      EOF
    end

  end

  def accepting_rosters?
    ['published', 'opened'].include?(self.state) #|| Market.override_close
  end

  def clean_publish
    Market.find_by_sql("select * from publish_clean_market(#{self.id})")
    reload
    if self.state == 'published'
      self.add_default_contests
    end
    self
  end
  #publish the market. returns the published market.
  def publish
    Market.find_by_sql("select * from publish_market(#{self.id})")
    reload
    total_expected = 0
    total_bets = 0
    market_players = self.market_players
    market_players.each do |mp|
      # calculate total ppg # TODO: this should be YTD
      total_exp = mp.player.total_points / (mp.player.total_games + 0.0001)
      # calculate ppg in last 5 games

      games = Game.where("game_time < now()").
                   where("(home_team = '#{mp.player[:team] }' OR away_team = '#{mp.player[:team] }')")

      events = StatEvent.where(:player_stats_id => mp.player.stats_id, game_stats_id: games.pluck('DISTINCT stats_id'), activity: 'points')
      recent_games = games.order("game_time DESC").first(5)
      recent_events = events.where(game_stats_id: recent_games.map(&:stats_id))

      if events.any?
        recent_exp = (StatEvent.collect_stats(recent_events)[:points] || 0 ).to_d/recent_games.count
        total_exp = (StatEvent.collect_stats(events)[:points] || 0 ).to_d / BigDecimal.new(mp.player.total_games)
      end

      # set expected ppg
      # TODO: HANDLE INACTIVE
      if mp.player.status != 'ACT' || events.count == 0
        mp.expected_points = 0
      else
        mp.expected_points = total_exp * 0.7 + recent_exp * 0.3
      end
      total_expected += mp.expected_points
    end
    market_players.each do |mp|
      # set total_bets & shadow_bets based on expected_ppg/ total_expected_ppg * 30000
      mp.bets = mp.shadow_bets = mp.initial_shadow_bets = mp.expected_points.to_f / (total_expected + 0.0001) * 300000
      total_bets += mp.bets
      mp.save!
    end
    self.expected_total_points = total_expected
    self.total_bets = self.shadow_bets = self.initial_shadow_bets = total_bets
    save!
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

=begin
  This is formatted as a json hash like so:
  {<unix-timestamp>: {paid: true}, ...]
=end
  def add_salary_bonus_time(time)
    bonus_times = JSON.parse(self.salary_bonuses || '{}')
    bonus_times[time.to_i] ||= {"paid" => false}
    self.update_attribute(:salary_bonuses, bonus_times.to_json)
  end

=begin
  This is formatted as a json array of arrays like so:
  [[<unix-timestamp, <percent-fill>], ...]
=end
  def add_fill_roster_time(time, percent)
    fill_times = JSON.parse(self.fill_roster_times || '[]')
    index = fill_times.find{|arr| arr[0] > time.to_i }
    if index.nil?
      fill_times.push([time.to_i, percent])
    else
      fill_times.insert(index, [time.to_i, percent])
    end
    self.update_attribute(:fill_roster_times, fill_times.to_json)
  end

  def fill_rosters
    fill_times = JSON.parse(self.fill_roster_times)
    percent = nil
    fill_times.each do |ft|
      percent = ft[1] if ft[0].to_i < Time.new.to_i
    end
    if percent
      self.fill_rosters_to_percent(percent)
    end
  end

  def fill_rosters_to_percent(percent)
    # iterate through /all/ non h2h unfilled contests and generate rosters to fill them up
    contests = self.contests.where("contest_type_id NOT IN(#{bad_h2h_type_ids.join(',')})")
    contests.where("(num_rosters < user_cap OR user_cap = 0) AND num_rosters != 0").find_each do |contest|
      contest.fill_with_rosters(percent)
    end
  end

  def bad_h2h_type_ids
    bad_h2h_types = self.contest_types.where(:name => ['27 H2H', 'h2h rr']).select do |ct|
      if (ct.name == '27 H2H' && [100, 1500].include?(ct.buy_in))# ||  # Fill H2H games of normal amounts
          #(ct.name == 'h2h rr' && [900, 9000].include?(ct.buy_in))
        false
      else
        true
      end
    end
    bad_h2h_types = bad_h2h_types.map(&:id).unshift(-1)
  end

  def remove_benched_players
    # select distinct rosters.* from rosters JOIN rosters_players ON rosters.id=rosters_players.roster_id JOIN players ON rosters_players.player_id=players.id WHERE rosters_players.market_id=326
    # AND (players.status = 'IR' OR players.removed);
    affected_rosters = Roster.select('distinct rosters.*'
                 ).joins('JOIN rosters_players ON rosters.id=rosters_players.roster_id JOIN players ON rosters_players.player_id=players.id'
                 ).where(["rosters_players.market_id = ? AND #{Player.bench_conditions}", self.id])
    affected_rosters.each{|r| r.swap_benched_players! }
  end

  def track_benched_players
    self.games.where('bench_counted_at <= ? AND (NOT bench_counted OR bench_counted IS NULL)', Time.new).each do |game|
      puts "#{Time.now} -- track game #{game.id}"
      Market.find_by_sql("SELECT * from track_benched_players('#{game.stats_id}')")
    end
    reload
  end

  def lock_players
    Market.find_by_sql("SELECT * from lock_players(#{self.id}, '#{self.game_type == 'regular_season' ? 't' : 'f'}')")
    reload
  end

  def tabulate_scores
    Market.find_by_sql("SELECT * FROM tabulate_scores(#{self.id})")
    reload
  end

  def deliver_bonuses
    bonus_times = JSON.parse(self.salary_bonuses || '{}')
    bonus_times.keys.sort.select{|time| time.to_i < Time.new.to_i && !bonus_times[time]['paid'] }.each do |time|
      self.rosters.update_all('remaining_salary = remaining_salary + 20000')
      self.contest_types.update_all('salary_cap = salary_cap + 20000')
      self.contests.where("contest_type_id NOT IN(#{bad_h2h_type_ids.join(',')})").each {|c| c.fill_reinforced_rosters } if self.game_type =~ /elimination/i
      bonus_times[time]['paid'] = true
    end
    self.update_attribute(:salary_bonuses, bonus_times.to_json)
    reload
  end

  def set_payouts
    self.contests.each{|c| c.set_payouts! }
    reload
  end

  def finish_games
    self.games_markets.select('games_markets.*').joins(
        'JOIN games ON games_markets.game_stats_id=games.stats_id'
    ).where("(games.status = 'closed' OR games.game_time < NOW() - INTERVAL '8 hours') AND games_markets.finished_at IS NULL").each{|gm| gm.finish! }
    reload
  end

  # close a market. allocates remaining rosters in this manner:
  def close
    raise "cannot close if state is not open" if state != 'opened'
    #cancel all un-submitted rosters
    self.rosters.where("state != 'submitted'").each {|r| r.cancel!('un-submitted before market closed') }
    self.contests.where(
        :contest_type_id => self.contest_types.where(:name => ['27 H2H', 'h2h rr']).map(&:id)
        ).where(:num_rosters => 1).each do |contest|
      contest.cancel!
    end

=begin
    self.contests.where("private AND num_rosters < user_cap").find_each do |contest|
      real_contest_entrants = contest.rosters.where(:is_generated => false).first
      if real_contest_entrants.length
        contest.rosters.each{|r| r.cancel!("No real entrants in contest")}
        contest.paid_at# there was a bug where we weren't decrementing num_rosters, this second clause can probably be removed after 11/2013
        next
      end
    end
#=begin
      # Iterate through unfilled private contests
      # Move rosters from unfilled public contests of the same type into these contests while able
      self.contests.where("private AND num_rosters < user_cap").find_each do |contest|
        contest_entrants = contest.rosters.map(&:owner_id)
        if contest.num_rosters == 0 or contest_entrants.length == 0 # there was a bug where we weren't decrementing num_rosters, this second clause can probably be removed after 11/2013
          contest.destroy
          next
        end
        Roster.select('rosters.*').where("rosters.contest_type_id = #{contest.contest_type_id} AND state = 'submitted' AND rosters.owner_id NOT IN(#{contest_entrants.join(', ')})"
             ).joins('JOIN contests c ON rosters.contest_id = c.id AND num_rosters < user_cap').limit(contest.user_cap - contest.num_rosters).each do |roster|
          next if contest_entrants.include?(roster.owner_id)
          contest_entrants.push(roster.owner_id)
          old_contest = roster.contest
          old_contest.num_rosters -= 1
          old_contest.save!
          tr = TransactionRecord.where(
            :contest_id => old_contest.id, :roster_id => roster.id
          ).first
          tr.update_attribute(:contest_id, contest.id)
          roster.contest_id, roster.cancelled_cause, roster.state  = contest.id, 'moved to under capacity private contest', 'in_progress'
          roster.contest.save!
          roster.save!
          roster.submit!(false)
        end
      end
=end
    self.fill_rosters_to_percent(1.0)
    self.lock_players
    self.state = 'closed'
    save!
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
      self.contests.where('cancelled_at IS NULL').find_each do |contest|
        contest.payday!
      end
      self.process_individual_predictions
      self.state = 'complete'
      self.save!
    end
  end

  def process_individual_predictions
    self.individual_predictions.where(finished: nil).each do |prediction|
      if prediction.player.benched?
        prediction.cancel!
      elsif prediction.won?
        customer_object = prediction.user.customer_object
        ActiveRecord::Base.transaction do
          customer_object.monthly_winnings += prediction.pt/10
          customer_object.save!
        end
        prediction.update_attribute(:award, prediction.pt)
      end

      prediction.update_attribute(:finished, true)
    end
  end

  def next_game_time_for_team(team)
    team = Team.find(team) if team.is_a?(String)
    game = self.games.where(['game_time > NOW() AND (home_team = ? OR away_team = ?)', team, team]).order('game_time asc').first
    game && game.game_time
  end

  def self.create_single_elimination_game(sport_id, player_market_name, team_market_name, expected_total_player_points, expected_total_team_points, opts = {})
    player_market = self.create!({
      :name => player_market_name,
      :expected_total_points => expected_total_player_points,
      :game_type => 'single_elimination',
      :sport_id => sport_id,
      :shadow_bets => 0,
      :shadow_bet_rate => 0.75,
      :published_at => Time.now + 1.minute
      }.merge(opts)
    )
    team_market = self.create!({
      :name => team_market_name,
      :expected_total_points => expected_total_team_points, # TODO: revisit this and how transformations work with team markets
      :game_type => 'team_single_elimination',
      :sport_id => sport_id,
      :shadow_bets => 0,
      :shadow_bet_rate => 0.75,
      :published_at => Time.now + 1.minute,
      :linked_market_id => player_market.id
      }.merge(opts)
    )
    player_market.update_attribute(:linked_market_id, team_market.id)
    Sport.find(sport_id).teams.each do |team| # Create all the team players if they don't exist
      begin
        p = Player.create!(
          :stats_id => "TEAM-#{team.abbrev}", # Don't change these
          :sport_id => sport_id,
          :name => team.name,
          :name_abbr => team.abbrev,
          :status => 'ACT',
          :total_games => 0,
          :total_points => 0,
          :team => Team.find(team.abbrev),
          :benched_games => 0
        )
        PlayerPosition.create!(:player_id => p.id, :position => "TEAM")
      rescue ActiveRecord::RecordNotUnique
      end
    end
    [player_market, team_market]
  end

  def add_single_elimination_game(game, price_multiplier = 1)
    [self, self.linked_market].each do |m|
      if m.opened_at.nil? || game.game_time < m.started_at
        m.opened_at = game.game_time.beginning_of_week + 24 * 60*60 + 11 * 60 * 60 # 9pm PST Tuesday
      end
      if m.started_at.nil? || game.game_time < m.started_at
        m.started_at = game.game_time
      end
      if m.closed_at.nil? || game.game_time > m.closed_at
        m.closed_at = game.game_time + 4.days # just some long time in the future. We'll be closing these manually
      end
      m.save!
      # Every sunday at 9pm PST within the date range gets a bonus
      m.started_at.to_date.upto(m.closed_at.to_date).map{|day| day.sunday? ? Time.new(day.year, day.month, day.day, 21, 0, 0, '-08:00') : nil }.compact.each do |time|
        m.add_salary_bonus_time(time)
      end
      m.add_fill_roster_time(game.game_time - 1.hour, 1.0)
      GamesMarket.create!(:market_id => m.id, :game_stats_id => game.stats_id, :price_multiplier => price_multiplier)
      [game.home_team, game.away_team].each do |team|
        m.market_players.where(:player_id => Player.where(:team => team).map(&:id)).update_all(:locked_at => next_game_time_for_team(team))
      end
    end
  end

  @@default_contest_types = [
    # Name, description,                                              max_entries, buy_in, rake, payout_structure
    {
      name: '5k',
      description: '5k Lollapalooza! $1000 for 1st prize!',
      max_entries: 600,
      buy_in: 1000,
      rake: 100000,
      # Payout lollapalooza: 1 1000 2 500 3 300 4-10 100 11-20 50 21-30 40 31-40 30 41-50 20 51-90 10
      payout_structure: '[100000, 50000, 30000, ' + # 1-3
                          '10000, 10000, 10000, 10000, 10000, 10000, 10000, ' +  # 4-10
                          '5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, ' + # 11-30
                          '5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, 5000, ' +
                          '4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, ' + # 31-45
                          '3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, ' + # 46-55
                          '2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000,' + # 56-65
                          '1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000,' + # 66-105
                          '1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000,' +
                          '1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000,' +
                          '1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000]',
      payout_description: "1st: $1k, 2nd: $500, 3rd: $300, 4th-10th: $100, 11th-30th: $50, 31st-45th: $40, 46th-55th: $30, 56th-65th: $20, 66th-105th: $10",
      takes_tokens: false,
      limit: 1
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
      limit: 1
    },
=end
#    {
#      name: '65/25/10',
#      description: '12 teams, top 3 winners take home $65, $25, $10',
#      max_entries: 12,
#      buy_in: 1000,
#      rake: 2000,
#      payout_structure: '[6500, 2500, 1000]',
#      payout_description: "$100 prize purse, 1st: $65, 2nd: $25, 3rd: $10",
#      takes_tokens: false,
#    },
    {
      name: '100/30/30',
      description: '12 teams, top 3 winners take home 100 FB, 30 FB, 30 FB',
      max_entries: 12,
      buy_in: 1500,
      rake: 2000,
      payout_structure: '[10000, 3000, 3000]',
      payout_description: "FB160 prize purse, 1st: FB100, 2nd: FB30, 3rd: FB30",
      takes_tokens: false,
    },
    {
      name: '27 H2H',
      description: 'h2h contest, winner takes home 27 FB',
      max_entries: 2,
      buy_in: 1500,
      rake: 300,
      payout_structure: '[2700]',
      payout_description: "FB27 prize purse, winner takes all",
      takes_tokens: false,
    },
=begin
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, 900FF entry fee, 9 games for 194FF per win',
      max_entries: 10,
      buy_in: 900,
      rake: 0.03,
      payout_structure: '[1746, 1552, 1358, 1164, 970, 776, 582, 388, 194, 0]',
      payout_description: "9 h2h games each pay out 194FF",
      takes_tokens: true,
    },
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, $9 entry fee, 9 games for $1.94 per win',
      max_entries: 10,
      buy_in: 900,
      rake: 0.03,
      payout_structure: '[1746, 1552, 1358, 1164, 970, 776, 582, 388, 194, 0]',
      payout_description: "9 h2h games each pay out $1.94",
      takes_tokens: false,
    },
    {
      name: 'h2h rr',
      description: '10 team, h2h round-robin contest, $90 entry fee, 9 games for $19.40 per win',
      max_entries: 10,
      buy_in: 9000,
      rake: 0.03,
      payout_structure: '[17460, 15520, 13580, 11640, 9700, 7760, 5820, 3880, 1940, 0]',
      payout_description: "9 h2h games each pay out $19.40",
      takes_tokens: false,
    }
=end
  ];

  def set_game_type
    unless self.game_type
      self.game_type = 'regular_season'
      self.save!
    end
  end

  #TODO: is this safe if run concurrently?
  def add_default_contests
    self.transaction do
      return if self.contest_types.length > 0
      @@default_contest_types.each do |data|
        next if data[:name].match(/\d+k/) && (!(self.name =~ /week|playoff/i) || Rails.env == 'test')
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
          takes_tokens: data[:takes_tokens],
          limit: data[:limit],
          positions: self.game_type == 'team_single_elimination' ? Array.new(6, 'TEAM').join(',') : Positions.for_sport_id(self.sport_id),
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
      csv << ["INSTRUCTIONS: Do not modify the first 4 columns of this sheet.  Fill out the Desired Shadow Bets column. Save the file as a .csv and send back to us", "Expected Fantasy Points ->"]
      csv << ["Canonical Id", "Name", "Team", "Position", "Desired Shadow Bets"]
      self.players.each do |player|
        csv << [player.stats_id, player.name.gsub(/'/, ''), player.team.abbrev, player.position]
      end
    end
  end

  def import_players_csv(data)
    self.state = nil
    self.save!
    self.publish

    count = 0
    total_bets = 0
    opts = {:col_sep => data.lines.to_a.split(';').length > 1 ? ';' : ','}
    data.rewind if data.respond_to?(:rewind) # Handle files
    CSV.parse(data, opts) do |row|
      count += 1
      if count == 1
        self.expected_total_points = row[2].empty? ? 1 : row[2]
      end
      next if count <= 2
      player_stats_id, shadow_bets = row[0], row[4]
      if !shadow_bets.blank?
        p = Player.where(:stats_id => player_stats_id).first
        if p.nil?
          puts "ERROR: NO PLAYER WITH STATS_ID #{player_stats_id} FOUND"
          next
        end
        puts "betting $#{shadow_bets} on #{p.name}"
        shadow_bets = shadow_bets.to_i * 100
      else
        shadow_bets = 0
      end
      mp = self.market_players.where("player_stats_id = '#{player_stats_id}'").first
      if mp.nil?
        puts "WARNING: No market player found with id #{player_stats_id}"
        next
      end
      #debugger# if mp.bets > mp.initial_shadow_bets ## PICK UP HERE, THIS SHOULD STOP
      mp.bets = (mp.bets || 0) - (mp.initial_shadow_bets || 0) + shadow_bets
      mp.shadow_bets = mp.initial_shadow_bets = shadow_bets
      mp.save!
      total_bets += shadow_bets
    end

    #set the shadow bets to whatever they should be
    puts "\nTotal bets: $#{total_bets/100}"
    # Re-count all these things, because bets may already be placed
    bets = {:bets => 0, :shadow_bets => 0}
    market_players = self.market_players.reload.map do |mp|
      bets[:bets] += mp.bets || 0
      bets[:shadow_bets] += mp.shadow_bets || 0
    end
    self.shadow_bets = self.initial_shadow_bets = bets[:shadow_bets]
    self.total_bets = bets[:bets]
    #TEMPORARY: artificially raise the price multiplier
    #self.price_multiplier = self.market_players.size / 50
    puts "using price multiplier: #{self.price_multiplier}"
    self.save!
    self
  end

  def market_duration
    if self.closed_at && self.started_at
      if (self.closed_at > self.started_at + 1.day)
        'week'
      else
        'day'
      end
    end
  end

  class << self
    attr_accessor :override_close
  end

  def self.override_market_close(&block)
    self.override_close = true
    Market.find_by_sql("SELECT set_session_variable('override_market_close', 'true')")
    result = yield
    self.override_close = false
    Market.find_by_sql("SELECT set_session_variable('override_market_close', null)")
    result
  end

  def nice_description
    # from niceMarketDesc filter in app/assets/javascripts/filters/filters.js
    # Day Desc
    if games.length > 1 && (closed_at - started_at) < 1.day
      return "All games on " + started_at.strftime('%a %d')
    end
    # Game Desc
    if games.length == 1
      return games[0].away_team + " at " + games[0].home_team + " on " + games[0].network
    end
    # Date Desc
    if (closed_at - started_at) > 1.day
      return started_at.strftime('%a %d') + " - " + closed_at.strftime('%a %d')
    end
  end

end
