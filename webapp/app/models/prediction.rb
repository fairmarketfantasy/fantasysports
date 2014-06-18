class Prediction < ActiveRecord::Base
  belongs_to :user

  attr_accessible :stats_id, :sport, :prediction_type, :game_stats_id, :user_id, :pt, :state, :created_at, :updated_at, :result, :award

  validates :stats_id, :uniqueness => {:scope => [:user_id, :stats_id, :prediction_type, :game_stats_id]}

  class << self

    def create_prediction(params, user)
      begin
        game_stats_id = params[:game_stats_id] || ''
        game = Game.where(stats_id: game_stats_id).first
        return [{error: "Game is closed"}, :unprocessable_entity] if game && game.game_time.utc < Time.now.utc

        prediction = user.predictions.new(stats_id: params[:predictable_id],
                                 sport: params[:sport],
                                 game_stats_id: game_stats_id,
                                 prediction_type: params[:prediction_type],
                                 pt: get_pt_value(params),
                                 state: 'submitted')
        prediction.pt = prediction.adjusted_pt(user: user)
        prediction.save!
        TransactionRecord.create!(user: user, event: "create_#{params[:prediction_type]}_prediction", amount: 15)
        Eventing.report(user, "create_#{params[:prediction_type]}_prediction", amount: 15)
        customer_object = user.customer_object
        customer_object.monthly_entries_counter += 1
        customer_object.save!
        [{msg: "#{params[:prediction_type].gsub('_', ' ')} prediction submitted successfully!"}, :ok]
      rescue
        [{error: "#{params[:prediction_type].gsub('_', ' ')} prediction creation failed!"}, :unprocessable_entity]
      end
    end

    #Process prediction for daily_wins
    def process_prediction(game, pr_type=nil)
      if pr_type.eql?('daily_wins')
        predictions = Prediction.where(prediction_type: pr_type, game_stats_id: game.stats_id).where.not(state: ['finished', 'canceled'])
        predictions.each do |prediction|
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
          prediction.update_attributes(state: 'finished', result: result, award: award)
          game.update_attributes(checked: true, status: 'finished')
        end if predictions.present?
      end
    end

    def prediction_made?(stats_id, prediction_type, game_stats_id='', user = nil)
      self.where(stats_id: stats_id, game_stats_id: game_stats_id, prediction_type: prediction_type, user_id: user.try(:id)).any?
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

    value = self.class.get_pt_value(prediction_type: self.prediction_type, predictable_id: self.stats_id).round(2)
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

  def adjusted_pt(opts = {})
    value = self.pt
    user = opts[:user]
    value *= user.customer_object.contest_winnings_multiplier if user
    value = 15.01.to_d if value < 15.to_d
    value.round(2)
  end

  private

  def self.get_pt_value(params)
    if params[:prediction_type].eql?('mvp')
      (Player.where(stats_id: params[:predictable_id]).first || Player.where(id: params[:predictable_id]).first).pt
    else
      PredictionPt.where(stats_id: params[:predictable_id], competition_type: params[:prediction_type]).first.pt
    end
  end
end
