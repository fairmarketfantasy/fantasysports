class GamePrediction < ActiveRecord::Base
  belongs_to :game, foreign_key: :game_stats_id
  belongs_to :team, foreign_key: :team_stats_id
  belongs_to :user
  belongs_to :game_roster
  validates_presence_of :user_id, :game_stats_id, :team_stats_id
  attr_protected

  scope :individual,   -> { where('game_roster_id=0')}

  scope :in_roster,   -> { where.not('game_roster_id=0')}
  scope :active, -> { where(state: ['in_progress', 'submitted'])}

  PT = BigDecimal.new(25)

  class << self

    def generate_games_data(opts = {})
      markets = SportStrategy.for(opts[:sport], opts[:category]).fetch_markets('regular_season')
      games = markets.map(&:games).flatten
      data = []
      games.each do |g|
        next if g.home_team_pt == g.away_team_pt or g.home_team_pt.nil? or g.away_team_pt.nil?

        h = {}
        home_team = Team.find(g.home_team)
        away_team = Team.find(g.away_team)
        %w(stats_id name logo_url).each do |field|
          h["home_team_#{field}".to_sym] = home_team.send(field.to_sym)
          h["away_team_#{field}".to_sym] = away_team.send(field.to_sym)
        end
        h[:home_team_pt] = g.home_team_pt
        h[:away_team_pt] = g.away_team_pt
        h[:game_time] = g.game_time
        h[:game_stats_id] = g.stats_id
        h[:disable_home_team] = prediction_made?(opts[:roster],
                                                 h[:game_stats_id],
                                                 h[:home_team_stats_id])
        h[:disable_away_team] = prediction_made?(opts[:roster],
                                                 h[:game_stats_id],
                                                 h[:away_team_stats_id])
        h[:disable_pt_home_team] = prediction_made?(opts[:user],
                                                 h[:game_stats_id],
                                                 h[:home_team_stats_id])
        h[:disable_pt_away_team] = prediction_made?(opts[:user],
                                                 h[:game_stats_id],
                                                 h[:away_team_stats_id])
        data << h
      end

      data
    end

    def generate_new_games_data(opts = {})
      markets = SportStrategy.for(opts[:sport], opts[:category]).fetch_markets('regular_season')
      games = markets.map(&:games).flatten
      data = []
      games.each do |g|
        next if g.home_team_pt == g.away_team_pt or g.home_team_pt.nil? or g.away_team_pt.nil?

        h = {stats_id:  g.stats_id,
             home_team: {},
             away_team: {}}

        home_team = Team.find(g.home_team)
        away_team = Team.find(g.away_team)
        game_name = "#{home_team.name}@#{away_team.name}"

        %w(stats_id name logo_url).each do |field|
          h[:home_team]["#{field}".to_sym] = home_team.send(field.to_sym)
          h[:away_team]["#{field}".to_sym] = away_team.send(field.to_sym)
        end

        h[:home_team][:game_time]     = g.game_time
        h[:away_team][:game_time]     = g.game_time
        h[:home_team][:game_stats_id] = g.stats_id
        h[:away_team][:game_stats_id] = g.stats_id
        h[:home_team][:game_name]     = game_name
        h[:away_team][:game_name]     = game_name
        h[:home_team][:is_home]       = true
        h[:away_team][:is_home]       = false

        h[:home_team][:pt]         = g.home_team_pt
        h[:away_team][:pt]         = g.away_team_pt
        h[:home_team][:is_added]   = prediction_made?(opts[:roster], h[:home_team][:game_stats_id], h[:home_team][:stats_id])
        h[:away_team][:is_added]   = prediction_made?(opts[:roster], h[:away_team][:game_stats_id], h[:away_team][:stats_id])
        h[:home_team][:disable_pt] = prediction_made?(opts[:user],   h[:home_team][:game_stats_id], h[:home_team][:stats_id])
        h[:away_team][:disable_pt] = prediction_made?(opts[:user],   h[:away_team][:game_stats_id], h[:away_team][:stats_id])

        if opts[:type] && opts[:type].eql?('pick5')
          h[:home_team][:is_added] = true
          h[:away_team][:is_added] = true
        end

        data << h
      end

      data
    end
    # owner is whether user or roster
    def prediction_made?(owner, game_stats_id, team_stats_id)
      return false unless owner

      # autofill hook
      return owner.include?(team_stats_id) if owner.is_a?(Array)

      conditions_hash = { game_stats_id: game_stats_id, team_stats_id: team_stats_id }

      # grab individual team predictions only
      conditions_hash.merge! :game_roster_id => 0 if owner.is_a? User

      owner.game_predictions.where(conditions_hash).any?
    end

    def create_prediction(opts = {})
      game = opts[:game]
      pt = opts[:team_stats_id] == game.home_team ? game.home_team_pt : game.away_team_pt
      prediction = User.find(opts[:user_id]).game_predictions.create!(game_stats_id: opts[:game_stats_id],
                                                                      team_stats_id: opts[:team_stats_id],
                                                                      pt: pt)
      prediction
    end
  end

  def remove_trade
    true
  end

  def charge_owner
    ActiveRecord::Base.transaction do
      customer_object = self.user.customer_object
      customer_object.monthly_contest_entries += Roster::FB_CHARGE
      customer_object.save!
    end
  end

  def cancel!
    user = self.user
    if self.game_roster.nil?
      ActiveRecord::Base.transaction do
        customer_object = user.customer_object
        customer_object.monthly_contest_entries -= Roster::FB_CHARGE
        customer_object.monthly_entries_counter -= 1
        customer_object.save!
      end
      TransactionRecord.create!(:user => user, :event => 'cancel_individual_prediction', :amount => Roster::FB_CHARGE * 1000)
      Eventing.report(user, 'CancelIndividualPrediction', :amount => Roster::FB_CHARGE * 1000)
    else
      self.game_roster.contest.game_rosters.map(&:cancel!) if self.game_roster.contest
    end

    puts 'cancel prediction'
    self.update_attribute(:state, 'canceled')
  end

  def won?
    raise "No winning team" if self.game.winning_team.nil?

    self.team_stats_id == self.game.winning_team
  end

  def home_team
    game.home_team == team.stats_id
  end

  def team_name
    team.name
  end

  def team_logo
    team.logo_url
  end

  def game_time
    game.game_time
  end

  def opposite_team
    game.teams.where("stats_id != '#{team_stats_id}'").first.name
  end

  def game_result
    return '' unless self.state == 'finished'
    "#{JSON.parse(self.game.home_team_status)['points']}:#{JSON.parse(self.game.away_team_status)['points']}"
  end

  def stats_id
    self.team_stats_id
  end

  def name
    self.team_name
  end

  def logo_url
    self.team_logo
  end

  def is_home
    self.home_team
  end

  def payout
    customer_object = user.customer_object
    amount_value = self.pt * 100 * customer_object.contest_winnings_multiplier
    ActiveRecord::Base.transaction do
      customer_object.monthly_winnings += amount_value
      customer_object.save!
    end
    TransactionRecord.create!(:user => user, :event => 'individual_prediction_win', :amount => amount_value)
    Eventing.report(user, 'IndividualPredictionWin', :amount => amount_value)
    user.update_attribute(:total_wins, user.total_wins.to_i + 1)
    self.update_attribute(:award, self.pt * customer_object.contest_winnings_multiplier)
  end

  def process
    puts "process game prediction #{self.id}"
    self.reload
    raise 'Should be submitted!' if self.state != 'submitted'

    if ['cancelled', 'postponed'].include?(self.game.status)
      self.cancel!
      self.reload
      return
    end

    if won? && self.game_roster.nil?
      charge_owner
      payout
    end

    self.update_attribute(:state, 'finished')
    puts 'finish prediction'
    self.reload
  end

  def current_pt
    return unless ['scheduled', 'live'].include?(self.game.status)

    value = if team.name == Team.where(stats_id: game.home_team).first.name
              game.home_team_pt
            elsif team.name == Team.where(stats_id: game.away_team).first.name
              game.away_team_pt
            else
              raise "Team not found for prediction #{self.id}"
            end
    return if pt - value == 0

    value
  end

  def pt_refund
    return unless current_pt

    (pt/current_pt * PREDICTION_CHARGE - PREDICTION_CHARGE).round(2)
  end

  def refund_owner
    ActiveRecord::Base.transaction do
      customer_object = user.customer_object
      customer_object.monthly_winnings += pt_refund * 100
      customer_object.save
    end
  end

  def current_pt
    return unless ['scheduled', 'live'].include?(self.game.status)

    value = if team.name == Team.where(stats_id: game.home_team).first.name
              game.home_team_pt
            elsif team.name == Team.where(stats_id: game.away_team).first.name
              game.away_team_pt
            else
              raise "Team not found for prediction #{self.id}"
            end
    return if pt - value == 0

    value
  end

  def pt_refund
    return unless current_pt

    (pt/current_pt * PREDICTION_CHARGE - PREDICTION_CHARGE).round(2)
  end

  def refund_owner
    ActiveRecord::Base.transaction do
      customer_object = user.customer_object
      customer_object.monthly_winnings += pt_refund * 100
      customer_object.save
    end
  end
end
