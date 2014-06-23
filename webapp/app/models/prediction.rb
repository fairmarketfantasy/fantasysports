class Prediction < ActiveRecord::Base
  belongs_to :user

  attr_accessible :stats_id, :sport, :prediction_type, :game_stats_id, :user_id, :pt, :state, :created_at, :updated_at, :result, :award

  validates :stats_id, :uniqueness => {:scope => [:user_id, :stats_id, :prediction_type, :game_stats_id]}

  class << self

    def create_prediction(params)
      begin
        game_stats_id = params[:game_stats_id] || ''
        game = Game.where(stats_id: game_stats_id).first
        return [{error: "Game is in progress now"}, :unprocessable_entity] if team_plays?(params[:predictable_id], params[:prediction_type])
        return [{error: "Game is closed"}, :unprocessable_entity] if game && game.game_time.utc < Time.now.utc

        user = params[:user]
        user.predictions.create!(stats_id: params[:predictable_id],
                                 sport: params[:sport],
                                 game_stats_id: game_stats_id,
                                 prediction_type: params[:prediction_type],
                                 pt: get_pt_value(params),
                                 state: 'submitted')
        TransactionRecord.create!(user: user, event: "create_#{params[:prediction_type]}_prediction", amount: 15)
        Eventing.report(user, "create_#{params[:prediction_type]}_prediction", amount: 15)
        customer_object = user.customer_object
        customer_object.monthly_entries_counter += 1
        customer_object.save!
        [{msg: "#{params[:prediction_type].gsub('_', ' ')} prediction submitted successfully!"}, :ok]
      rescue Exception => e
        logger.warn e
        [{error: "#{params[:prediction_type].gsub('_', ' ')} prediction creation failed!"}, :unprocessable_entity]
      end
    end

    #Process prediction for daily_wins
    def process_prediction(game, pr_type=nil)
      if pr_type.eql?('daily_wins')
        predictions = Prediction.where(prediction_type: pr_type, game_stats_id: game.stats_id).where.not(state: ['finished', 'canceled'])
        predictions.each do |prediction|
          puts "process prediction #{prediction.id}"

          if prediction.won?
            result = 'Win'
            award  = prediction.pt
            event  = "won_#{pr_type}_prediction"
          end
          if prediction.lose?
            result = 'Lose'
            award  = 0
            event  = "lose_#{pr_type}_prediction"
          end
          if prediction.dead_heat?
            result = 'Dead heat'
            res    = prediction.pt.to_d / 2
            award  = (res >= 13.5) ? res : 13.5
            event  = "dead_heat_#{pr_type}_prediction"
          end

          user = prediction.user
          customer_object = user.customer_object
          ActiveRecord::Base.transaction do
            customer_object.monthly_contest_entries += 1.5
            customer_object.monthly_winnings += award * 100
            customer_object.save
          end

          TransactionRecord.create!(user: user, event: event, amount: award)
          Eventing.report(user, event, amount: award)
          prediction.update_attribute(:state, 'finished')
          prediction.update_attribute(:result, result)
          prediction.update_attribute(:award, award)
          game.update_attributes(checked: true, status: 'finished')
        end
      end
    end

    def prediction_made?(stats_id, prediction_type, game_stats_id='', user = nil)
      self.where(stats_id: stats_id, game_stats_id: game_stats_id, prediction_type: prediction_type, user_id: user.try(:id)).any?
    end

    def team_plays?(stats_id, prediction_type)
      if prediction_type.eql?('mvp')
        team_stats_id = (Player.where(stats_id: stats_id).first || Player.where(id: stats_id).first).team.stats_id
      else
        team_stats_id = stats_id
      end
      group   = Team.where(stats_id: team_stats_id).first.group_id
      teams   = Team.where(group_id: group).map(&:stats_id).compact
      p_teams = Player.where(team: teams).map(&:stats_id).compact
      team_ids = teams + p_teams

      games = Game.where(home_team: team_ids) + Game.where(away_team: team_ids)
      games.uniq.each do |game|
        return true if (game.game_time.utc < Time.now.utc) && (game.game_time.utc + 6.hours > Time.now.utc)
      end
      false
    end
  end

  def charge_owner
    ActiveRecord::Base.transaction do
      customer_object = self.user.customer_object
      customer_object.monthly_contest_entries += Roster::FB_CHARGE
      customer_object.save!
    end
  end

  def cancel!
    raise NotImplementedError
  end

  #These 3 methods will work only for 'daily_wins'!
  def won?
    return true if (game.home_team_status.to_i > game.away_team_status.to_i) and game.home_team.eql?(self.stats_id)
    return true if (game.home_team_status.to_i < game.away_team_status.to_i) and game.away_team.eql?(self.stats_id)
    false
  end

  def lose?
    return true if (game.home_team_status.to_i < game.away_team_status.to_i) and game.home_team.eql?(self.stats_id)
    return true if (game.home_team_status.to_i > game.away_team_status.to_i) and game.away_team.eql?(self.stats_id)
    false
  end

  def dead_heat?
    return true if game.home_team_status.to_i == game.away_team_status.to_i
    false
  end

  def game
    Game.where(stats_id: self.game_stats_id).first
  end

  def current_pt
    return unless self.state == 'submitted'

    value = self.class.get_pt_value(type: self.prediction_type, user: self.user,
                                    predictable_id: self.stats_id,
                                    game_stats_id: game.try(:stats_id))
    return if pt - value <= 0

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
      customer_object.save!
      TransactionRecord.create!(user: user, event: 'trade_prediction', amount: pt_refund)
    end
  end

  private

  def self.get_pt_value(params)
    type = params[:type] || params[:prediction_type]
    if type.eql?('mvp')
      (Player.where(stats_id: params[:predictable_id]).first || Player.where(id: params[:predictable_id]).first).adjusted_pt(params)
    else
      Team.where(stats_id: params[:predictable_id]).first.pt(params)
    end
  end
end
