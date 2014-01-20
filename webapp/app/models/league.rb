class League < ActiveRecord::Base
  attr_protected
  has_many :contests
  has_many :league_memberships
  has_many :users, :through => :league_memberships
  before_create :create_identifier

  def create_identifier
    self.identifier = self.name.gsub(/['"-]/, '').gsub(' ', '_')
  end

  def self.find_or_create_from_opts(opts) # name, buy_in, max_entries, takes_tokens, salary_cap
    if opts[:league_id]
      league = League.find(opts[:league_id])
    else
      league = League.create!(
        :name => opts[:league_name],
        :buy_in => opts[:buy_in],
        :max_entries => opts[:max_entries],
        :takes_tokens => opts[:takes_tokens],
        :salary_cap => opts[:salary_cap],
        :start_day => (opts[:market].started_at - 6.hours).strftime("%w").to_i + 1,
        :duration => opts[:market].market_duration,
      )
      league.users << opts[:user]
    end
    league
  end

  def contest_type
    contest = self.contests.last
    if contest
      contest.contest_type.duplicate_into_market(current_market)
    else
      current_market.contest_types.where(
            :buy_in => self.buy_in,
            :max_entries => self.max_entries,
            :takes_tokens => self.takes_tokens,
            :salary_cap => self.salary_cap).first_or_create
    end
  end

  def current_market
    @market ||= begin
        market = Market.where(["closed_at > ?", Time.new - 6.hours]).order('closed_at asc')
        if self.duration == 'week'
          market = market.where("name ILIKE '%week%'")
        else # day
          market = market.where(["to_char(started_at - interval '6 hours', 'D') =  ? AND closed_at - started_at < '2 days'", self.start_day.to_s])
        end
        debugger
        market.first
    end
  end

  def current_contest
    @contest ||= begin
        market = current_market
        raise HttpException.new(404, "Sorry, That league isn't running this week.  Try another game!") unless market
        contest = Contest.where(:market_id => market.id, :league_id => self.id).first
        if !contest
          contest = Contest.create!(
            market: market,
            owner_id: self.users.first.id, # TODO: make a commissioner
            user_cap: contest_type.max_entries,
            buy_in: contest_type.buy_in,
            contest_type: contest_type,
            private: true,
            league_id: self.id,
          )
        end
        contest
    end
  end

end
