class CardsController < ApplicationController

  def index
    if current_user.customer_object
      render_api_response current_user.customer_object
    else
      render_api_response []
    end
  end

  def create
    begin
      co = CustomerObject.create(user: current_user, token: params[:card][:token])
    rescue => e
      err = e.message
    end
    if co
      render_api_response co
    else
      render json: {error: err}
    end
  end
end