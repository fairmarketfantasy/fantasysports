class PlayerPredictionsController < ApplicationController
  def create
    raise HttpException.new(402, 'Agree to terms!') unless current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, 'Unpaid subscription!') if !current_user.active_account? && !current_user.customer_object.trial_active?

    PlayerPrediction.create_prediction(params, current_user)

    render :text => 'Player prediction submitted successfully!', :status => :ok
  end

  def show
    prediction = PlayerPrediction.find(params[:id])

    render_api_response prediction
  end

  def mine
    sport = Sport.where(:name => params[:sport]).first if params[:sport]
    predictions = current_user.player_predictions

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
