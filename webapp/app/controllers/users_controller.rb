class UsersController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:create, :update]

  def index
    render_api_response current_user
  end

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

  def withdraw_money
    authenticate_user!
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    if current_user.recipient.transfer(params[:amount])
      render_api_response current_user.reload
    end
  end

end
