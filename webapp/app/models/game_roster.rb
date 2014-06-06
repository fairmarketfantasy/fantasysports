class GameRoster < ActiveRecord::Base
  belongs_to :game
  belongs_to :contest
  belongs_to :contest_type
  belongs_to :owner, class_name: "User", foreign_key: :owner_id
  has_many :game_predictions

  #scope :with_perfect_score, ->(score) { select("game_rosters.*, #{score.to_f} as perfect_score") }
  attr_protected

  ROOM_NUMBER = 5
  FB_CHARGE = 1.5.to_d

  scope :submitted, -> { where(state: 'submitted')}
  scope :active, -> { where(state: 'submitted') }

  before_destroy :pre_destroy

  class << self
    def sample(sport)
      games = SportStrategy.for(sport, 'fantasy_sports').fetch_markets('regular_season').map(&:games).flatten
      games = games.select { |i| i.home_team_pt.present? and i.away_team_pt.present? }.sample(5).sort_by(&:game_time)

      data = []
      games.each_with_index do |game, i|
        team_stats_id = game.teams.sample.stats_id
        pt = team_stats_id == game.home_team ? game.home_team_pt : game.away_team_pt
        data << GamePrediction.new(state: 'submitted', game_stats_id: game.id, pt: pt, team_stats_id: team_stats_id, position_index: i)
      end

      data
    end

    def generate(user, contest_type, sport = 'MLB')
      day_games = SportStrategy.for(sport, 'fantasy_sports').fetch_markets('regular_season').map(&:games).flatten
      games = day_games.select { |i| i.home_team_pt.present? and i.away_team_pt.present? }.sample(5)
      data = []
      game = day_games.first
      roster = user.game_rosters.create!(state: 'submitted',
                                         contest_type_id: contest_type.id,
                                         started_at: game.game_time - 5.minutes,
                                         day: game.game_day,
                                         is_generated: true)
      games.each_with_index do |game, i|
        team_stats_id = game.teams.sample.stats_id
        pt = team_stats_id == game.home_team ? game.home_team_pt : game.away_team_pt
        roster.game_predictions.create!(user_id: user.id,
                                        game_stats_id: game.stats_id,
                                        team_stats_id: team_stats_id,
                                        pt: pt,
                                        position_index: i)
      end

      roster
    end

    def json_view(arr)
      required_fields = [:game_stats_id, :team_stats_id, :home_team, :team_logo,
                         :team_name, :game_time, :opposite_team, :pt, :position_index]
      arr.to_json(:only => [:id, :score, :state, :contest_id, :contest_rank, :owner_id, :paid_at, :amount_paid, :expected_payout],
                  :methods => [:room_number, :owner_name, :contest_rank_payout, :perfect_score],
                  :include => { :game_predictions => {:methods => required_fields} } )
    end
  end

  def room_number
    5
  end

  def submit!
    set_contest = Contest.where("contest_type_id = ?
          AND (user_cap = 0 OR user_cap > 12
              OR (num_rosters - num_generated < user_cap))
          AND NOT private", contest_type.id).where.not(owner_id: self.owner_id).order('id asc').first
    if set_contest.nil?
      set_contest = Contest.create!(owner_id: self.owner_id, buy_in: contest_type.buy_in, user_cap: contest_type.max_entries,
                                    market_id: Market.first.id, contest_type_id: contest_type.id)
    end

    set_contest.num_generated += 1 if self.is_generated?
    set_contest.num_rosters += 1
    set_contest.save!
    set_contest.reload
    if set_contest.num_rosters > set_contest.user_cap && set_contest.user_cap != 0
      removed_roster = set_contest.game_rosters.where('is_generated = true AND NOT cancelled').first
      if removed_roster.nil?
        set_contest = Contest.create!(owner_id: self.owner_id, buy_in: contest_type.buy_in, user_cap: contest_type.max_entries,
                                      market_id: Market.first.id, contest_type_id: contest_type.id)
        set_contest.num_rosters += 1
        set_contest.num_generated += 1
      else
        removed_roster.cancel!("Removed for a real player")
        set_contest.num_rosters -= 1
        set_contest.num_generated -= 1
      end
      set_contest.save!
    end
    self.contest = set_contest
    self.save!
  end

  def cancel!(reason = 'Game canceled')
    self.with_lock do
      if self.state == 'submitted'
        Roster.transaction do
          #self.owner.payout(:monthly_entry, 1.5.to_d, :event => 'cancelled_roster', :roster_id => self.id, :contest_id => self.contest_id)
          self.state = 'canceled'
          self.cancelled = true
          self.cancelled_at = Time.new
          self.cancelled_cause = reason
          self.save!
          if self.contest
            self.contest.num_rosters -= 1
            self.contest.save!
          end
        end
      end
    end
  end

  def charge_account
    self.owner.charge(:monthly_entry, Roster::FB_CHARGE, :event => 'buy_in',
                      :contest_id => self.contest_id)
  end

  def contest_rank_payout # api compatible attr name
    self.expected_payout
  end

  def owner_name
    if self.is_generated?
      User::SYSTEM_USERNAMES[self.id % User::SYSTEM_USERNAMES.length]
    else
      self.owner.username
    end
  end

  def perfect_score
    self.contest.game_rosters.map(&:score).max
  end

  # huck, as long as we have same behaviour with Roster class
  def set_records!
  end

  def process
    puts "process game roster #{self.id}"
    if game_predictions.where(state: 'canceled').any?
      self.update_attribute(:state, 'canceled')
      return
    end

    sum = 0.to_d
    self.game_predictions.where(state: 'finished').each do |prediction|
      if prediction.won?
        sum += (prediction.pt || 0)
      else
        prediction.update_attribute(:pt, 0)
      end
    end

    self.update_attribute(:score, sum)
    self.update_attribute(:state, 'finished') if self.game_predictions.where("state != 'finished'").empty?
  end

  def pre_destroy
    self.game_predictions.destroy_all
  end
end
