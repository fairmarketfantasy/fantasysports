class IndividualPredictionsController < ApplicationController
  def create
    raise HttpException.new(402, "Agree to terms!") unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, "Unpaid subscription!") if !current_user.active_account? && !current_user.customer_object.trial_active?

    player = Player.where(stats_id: params[:player_id]).first
    prediction = current_user.individual_predictions.create(player_id: player.id,
                                                            roster_id: params[:roster_id],
                                                            market_id: params[:market_id],
                                                            pt: IndividualPrediction::PT)
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

    prediction.submit!
    render :text => 'Individual prediction submitted successfully!', :status => :ok
  end

  def show
    prediction = IndividualPrediction.find(params[:id])

    render_api_response individual_prediction
  end

  def mine
    sport = Sport.where(:name => params[:sport]).first if params[:sport]
    sport ||= Sport.where('is_active').first
    predictions = current_user.individual_predictions

    if params[:historical]
      page = params[:page] || 1
      predictions = predictions.where(finished: true)
    else
      predictions = predictions.where(finished: nil)
    end

    render_api_response predictions
  end
end
