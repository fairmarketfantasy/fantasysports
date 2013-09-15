class UsersController < ApplicationController
  skip_before_filter :authenticate_user!

  def show
    user = User.find(params[:id])
    render_api_response user
  end

  def add_money
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    current_user.customer_object.set_default_card(params[:card_id])
    if current_user.customer_object.charge(params[:amount])
      render_api_response current_user
    end
  end
end
