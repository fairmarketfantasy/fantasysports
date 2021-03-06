class Player < ActiveRecord::Base
  attr_protected
  belongs_to :sport
  #belongs_to :team, :foreign_key => 'team' # THe sportsdata data model is so bad taht sometimes this is an abbrev, sometimes its a stats id
  def team
    return self[:team] if self[:team].is_a? Team
    team = if self[:team].split('-').count > 2 or self[:team].to_i > 0 or self.sport.name == 'FWC'
      Team.where(:stats_id => self[:team])
    else
      Team.where(:abbrev => self[:team])
    end
    team.first
  end
  has_many :stat_events, :foreign_key => 'player_stats_id', :inverse_of => :player, :primary_key => 'stats_id'
  has_many :positions, :class_name => 'PlayerPosition'
  has_many :individual_predictions
  has_many :members, as: :memberable
  has_many :competitions, through: :members

  def purchase_price; self[:purchase_price]; end
  def buy_price; self[:buy_price]; end
  def swapped_player_name; self[:swapped_player_name]; end
  def sell_price; self[:sell_price]; end
  def score; self[:score]; end
  def locked; self[:locked]; end
  def market_id; self[:market_id]; end
  def is_eliminated; self[:is_eliminated]; end
  def position; self[:position]; end

  # Some positions are never used in NFL
  #default_scope { where("position NOT IN('OLB', 'OL')") }

  has_many :market_players
  has_many :rosters_players
  has_and_belongs_to_many :rosters, join_table: 'rosters_players'

  scope :autocomplete, ->(str)        { where("name ilike '%#{str}%'") }
  scope :on_team,      ->(team)       { where(team: team)}
  scope :in_market,    ->(market)     { where(team: market.games.map{|g| g.teams.map{|t| [t.abbrev, t.stats_id]} }.flatten) }
  scope :in_game,      ->(game)       { where(team: game.teams.map{|t| [t.abbrev, t.stats_id]}.flatten ) }
  scope :in_position,  ->(position)   { select('players.*, player_positions.position').joins('JOIN player_positions ON players.id=player_positions.player_id').where(["player_positions.position = ?", position]) }
  scope :in_position_by_market_id, -> (market_id, position) { select('players.*, market_players.position').
      where(['market_players.position = ? AND market_players.market_id = ?', position, market_id]) }
  scope :normal_positions,      ->(sport_id) { select('players.*, player_positions.position'
                                    ).joins('JOIN player_positions ON players.id=player_positions.player_id'
                                    ).where("player_positions.position IN( '#{Positions.for_sport_id(sport_id).split(',').join("','") }')") }
  scope :order_by_ppg,          ->(dir = 'desc') { order("ppg #{dir}") }
  scope :with_purchase_price,   -> { select('players.*, rosters_players.purchase_price') } # Must also join rosters_players
  scope :with_market,           ->(market) { select('players.*').select(
                                             "#{market.id} as market_id, mp.is_eliminated, mp.score, mp.locked"
                                           ).joins("JOIN market_players mp ON players.id=mp.player_id AND mp.market_id = #{market.id}") }
  scope :with_prices_for_players, -> (market, buy_in, player_ids) {
      select('players.*, mp.*').joins(
        "JOIN market_prices_for_players(#{market.id}, #{buy_in}, #{player_ids.push(-1).join(', ') }) mp ON mp.player_id=players.id")
  }

  # THIS IS REALLY SLOW, favor market_prices_for_players
  scope :with_prices,           -> (market, buy_in) {
      select('players.*, market_prices.*').joins("JOIN market_prices(#{market.id}, #{buy_in}) ON players.id = market_prices.player_id")
  }

  scope :benched,   -> { where(Player.bench_conditions) }
  scope :active, -> () {
    where("status = 'ACT' OR status = 'A' OR STATUS = 'M' AND NOT removed AND NOT out")
  }

  scope :purchasable_for_roster, -> (roster) {
    select(
      "players.*, player_positions.position, buy_prices.buy_price as buy_price, buy_prices.is_eliminated"
    ).joins("JOIN buy_prices(#{roster.id}) as buy_prices on buy_prices.player_id = players.id JOIN player_positions ON players.id=player_positions.player_id")
  }

  scope :with_sell_prices, -> (roster) {
    select(
      "players.*, sell_prices.locked, sell_prices.score, sell_prices.purchase_price as purchase_price, sell_prices.sell_price as sell_price"
    ).joins( "JOIN sell_prices(#{roster.id}) as sell_prices on sell_prices.player_id = players.id" )
  }
  scope :sellable, -> { where('sell_prices.locked != true' ) }

  scope :with_flags, -> { where("team != 'MVP'") }

  def self.bench_conditions
    "(players.out = true OR players.status = 'IR' OR players.removed)"
  end

  def benched?
    self.out || self.status == 'IR' || self.removed
  end

  def headshot_url(size = 65) # or 195
    s3_url = 'https://fairmarketfantasy-prod.s3-us-west-2.amazonaws.com'
    default = "#{s3_url}/headshots/#{stats_id}/#{size}.jpg"

    return nil if position == 'DEF'
    return default if self.team.nil?
    if sport.name == 'MLB'
      if (positions.first.try(:position) =~ /(P|SP|RP)/).present?
        return ActionController::Base.helpers.asset_path 'pitcher_icon.png'
      else
        return ActionController::Base.helpers.asset_path 'hitter_icon.png'
      end
    elsif sport.name == 'FWC'
      return team.logo_url
    end

    return default
  end

  def next_game_at # Requires with_market scope
    return nil unless self.market_id
    game = Market.find(self.market_id).games.order('game_time asc').select{|g| [g.home_team, g.away_team].include?(self.team)}.first
    return game && game.game_time - 5.minutes
  end

  def benched_games
    self.removed? ? 100 : super
  end

  def calculate_ppg
    sport_name = self.sport.name

    if sport_name == 'MLB'
      value = self.calculate_average({ player_ids: self.stats_id, position: self.positions.map(&:position).first },nil, true)
      value = 0 if value.is_a? Array
    else
      played_games_ids = StatEvent.where("player_stats_id='#{self.stats_id}' AND quantity != 0" ).
                                   pluck('DISTINCT game_stats_id')
      events = StatEvent.where(player_stats_id: self.stats_id,
                               game_stats_id: played_games_ids)
      return unless events.any? || played_games_ids.count == 0

      value = events.map(&:point_value).reduce(:+) / played_games_ids.count
    end

    value = value.round == 0 ? nil : value
    self.update_attribute(:ppg, value)
  end

  # third param - hook for return Fantasy Points
  def calculate_average(params, current_user, ret_fp = false)
    sport_name = self.sport.name
    played_games_ids = StatEvent.where("player_stats_id='#{params[:player_ids]}' AND quantity != 0").
                                 pluck('DISTINCT game_stats_id')
    games = Game.where(stats_id: played_games_ids)
    last_year_ids = games.where(season_year: (Time.now.utc - 4).year - 1).map(&:stats_id).uniq
    this_year_ids = games.where(season_year: (Time.now.utc - 4).year).select { |i| i.stat_events.any? }.map(&:stats_id).uniq
    events = StatEvent.where(player_stats_id: params[:player_ids],
                             game_stats_id: played_games_ids)
    if games.last and sport_name == 'MLB'
      recent_games = games.where(season_year: (Time.now.utc - 4).year).order("game_time DESC").first(50)
    else
      recent_games = games.order("game_time DESC").first(5)
    end
    recent_ids = recent_games.map(&:stats_id)
    recent_ids.uniq!
    recent_events = events.where(game_stats_id: recent_ids)
    last_year_events = events.where(game_stats_id: last_year_ids)
    this_year_events = events.where(game_stats_id: this_year_ids)
    recent_stats = SportStrategy.for(sport_name).collect_stats(recent_events, params[:position])
    last_year_stats = SportStrategy.for(sport_name).collect_stats(last_year_events, params[:position])
    this_year_stats = SportStrategy.for(sport_name).collect_stats(this_year_events, params[:position])
    total_stats = SportStrategy.for(sport_name).collect_stats(events, params[:position])

    if params[:market_id] == 'undefined'
       bid_ids = []
    else
       bid_ids = current_bid_ids(params[:market_id], self.id, current_user.id) if current_user
       bid_ids ||= []
    end

    data = []
    total_stats.each do |k, v|
      if games.last.sport.name == 'MLB'
        ip_per_game = 9.0
        #last_year_points = last_year_stats[k] || 0.to_d
        #this_year_points = (this_year_stats[k] || 0).to_d/this_year_ids.count if this_year_ids.count != 0
        if k == 'Era (earned run avg)'.to_sym
          recent = ip_per_game * this_year_stats[k].to_f/this_year_stats[:'Inning Pitched'].to_f
          history_val = if self.total_games.zero?
                          recent
                        else
                          era = (last_year_stats[k].to_f*self.total_games + this_year_stats[k].to_f)
                          ip = this_year_stats[:'Inning Pitched'].to_f + last_year_stats[:'Inning Pitched'].to_f*self.total_games
                          ip_per_game * era/ip
                        end
        else
          history_val = ((last_year_stats[k] || 0.to_d)*self.total_games + (this_year_stats[k] || 0).to_d)/(this_year_ids.count + self.total_games)
          #history = last_year != 0 ? [last_year * (last_year - 2 * this_year)/last_year + this_year, 0].max : this_year
          recent = (recent_stats[k] || 0.to_d)/recent_ids.count if recent_ids.count != 0
          recent ||= 0
        end

        if last_year_ids.count == 0
          Honeybadger.notify(
            :error_class   => "NoLastYearMLBStats",
            :error_message => "NoLastYearMLBStats: #{Player.where(stats_id: params[:player_ids]).name} #{self.name}",
            :parameters    => params
          )
        end

        if this_year_stats[:'Inning Pitched'].to_i > 15 or self.stat_events.where(:activity => 'At Bats').select { |st| st.game.game_time.year == Time.now.year }.size > 50
          koef = 0.2
        else
          # batter
          if (self.positions.first.try(:position) =~ /(C|1B|DH|2B|3B|SS|OF)/).present?
            koef = 0.2*(self.stat_events.where(:activity => 'At Bats').select { |st| st.game.game_time.year == Time.now.year }.size/50.0)
          else
            koef = 0.2*(this_year_stats[:'Inning Pitched'].to_i/15.0)
          end
        end

        value = koef.to_d * recent.to_f + (1.0 - koef).to_d * history_val.to_f

        value = this_year_stats[k].to_f/this_year_ids.count if k != 'Era (earned run avg)'.to_sym && (self.legionnaire? || self.total_games.zero?)
        return value if ret_fp && k == 'Fantasy Points'.to_sym
      else
        value = v.to_d / BigDecimal.new(played_games_ids.count)
        value = value * 0.7 + (recent_stats[k] || 0.to_d)/recent_ids.count * 0.3
      end

      value = value.round(2)
      next if value == 0

      bid_less = false
      bid_more = false
      if bid_ids.any?
        less = EventPrediction.where(event_type: k.to_s, diff: 'less', individual_prediction_id: bid_ids).count
        more = EventPrediction.where(event_type: k.to_s, diff: 'more', individual_prediction_id: bid_ids).count
        value = with_formula_value(value, bid_ids.count, more, less)
        bid_less = true if less != 0
        bid_more = true if more != 0
      end

      less_pt = IndividualPrediction.get_pt_value(value, 'less')
      more_pt = IndividualPrediction.get_pt_value(value, 'more')

      data << { name: k, value: value, bid_less: bid_less, bid_more: bid_more, less_pt: less_pt, more_pt: more_pt }
    end

    adjust_wins(data, this_year_stats)
  end

  def adjusted_pt(opts = {})
    value = self.pt
    return if value.nil? || value == 0

    user = opts[:user]
    value *= user.customer_object.contest_winnings_multiplier if user
    value = 15.01.to_d if value < 15.to_d
    value.round(2)
  end

  private

  def current_bid_ids(market_id, player_id, current_user_id)
    IndividualPrediction.where(user_id: current_user_id,
                               market_id: market_id,
                               player_id: player_id).pluck(:id)
  end

  def with_formula_value(value, total, more, less)
    value = value * (20 + total + (more - less)).to_d / (20 + total).to_d
    value.round(2)
  end

  def adjust_wins(data, this_year_stats)
    wins = data.find { |i| i[:name ] == 'Wins'.to_sym }
    if wins && this_year_stats[:'Inning Pitched'] < 50
      wins[:value] = 0.2.to_d if wins[:value] < 0.2
      wins[:value] = 0.7.to_d if wins[:value] > 0.7
    end

    data
  end
end
