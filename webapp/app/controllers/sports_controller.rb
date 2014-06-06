class SportsController < ApplicationController
  skip_before_filter :authenticate_user!, only: [:home]

  def home
    raise HttpException.new(402, 'Agree to terms!') unless !current_user || current_user.customer_object.has_agreed_terms?
    raise HttpException.new(402, 'Unpaid subscription!') if current_user && !current_user.active_account? && !current_user.customer_object.trial_active?

    render json: SportStrategy.for(params[:sport], params[:category]).home_page_content(current_user).to_json
  end

  def create_prediction
    if params[:sport].eql?('FWC')
      message = Prediction.create_prediction(params, current_user)
      render json: message, status: message[:status]
    else
      render SportStrategy.for(params[:sport], params[:category]).create_prediction(params, current_user)
    end
  end
end
