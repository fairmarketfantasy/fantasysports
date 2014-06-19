class SportsController < ApplicationController
  skip_before_filter :authenticate_user!, only: [:home]

  def home
    raise HttpException.new(402, 'Agree to terms!') unless !current_user || current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, 'Unpaid subscription!') if current_user && !current_user.active_account? && !current_user.customer_object.trial_active?

    render json: SportStrategy.for(params[:sport], params[:category]).home_page_content(current_user).to_json
  end

  def create_prediction
    params[:user] = current_user
    if params[:sport].eql?('FWC')
      message, status = Prediction.create_prediction(params)
      render json: message, status: status
    else
      raise 'Not implemented!'
    end
  end

  def trade_prediction
    prediction = if params[:sport].eql?('FWC')
                   Prediction.find(params[:id])
                 else
                   GamePrediction.find(params[:id])
                 end
    if (prediction.game && prediction.game.game_time.utc < Time.now.utc) || prediction.state != 'submitted'
      raise HttpException.new(422, 'Trade error: prediction is not submitted')
    else
      prediction.refund_owner
      prediction.destroy!

      render :json => { 'msg' => 'You trade your prediction' }, :status => :ok
    end
  end
end
