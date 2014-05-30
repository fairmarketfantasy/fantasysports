class IndividualPredictionsController < ApplicationController
  def create
    raise HttpException.new(402, "Agree to terms!") unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, "Unpaid subscription!") if !current_user.active_account? && !current_user.customer_object.trial_active?

    prediction = IndividualPrediction.create_individual_prediction(params, current_user)
    params[:events].each do |event|
      if prediction.event_predictions.where(event_type: event[:name], value: event[:value], diff: event[:diff]).first
        return render 'You already have such prediction!', status: :unprocessable_entity
      end
      event_prediction = prediction.event_predictions.create(event_type: event[:name],
                                                             value: event[:value],
                                                             diff: event[:diff])
      if event_prediction.errors.any?
        return render :text => k + ' ' + event_prediction.errors.full_messages.join(', '),
          status: :unprocessable_entity
      end
    end

    render :json => { 'msg' => 'Individual prediction submitted successfully!' }, :status => :ok
  end

  def show
    prediction = IndividualPrediction.find(params[:id])

    render_api_response prediction
  end

  # we have to use 1 query for individual, game and MVP predictions
  def mine
    category = Category.where(name: params[:category]).first || Category.where(name: 'fantasy_sports').first
    sport = category.sports.where(:name => params[:sport]).first if params[:sport]
    sport ||= Sport.where('is_active').first
    if params[:category] && params[:category] == 'sports' and params[:sport] == 'MLB'
      predictions = current_user.game_predictions.where(:game_roster_id => 0).joins('JOIN games g ON game_predictions.game_stats_id=g.stats_id').order('game_time asc')
    else
      predictions = current_user.individual_predictions.joins('JOIN markets m ON individual_predictions.market_id=m.id').
          where(['m.sport_id = ?', sport.id]).order('closed_at desc')
    end
    page = params[:page] || 1
    if params[:historical]
      predictions = predictions.where(state: ['finished', 'canceled'])
    elsif params[:all]
      predictions = predictions
    else
      predictions = predictions.where(state: 'submitted')
    end

    render_api_response predictions.page(page)
  end
end
