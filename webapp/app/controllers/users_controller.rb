class UsersController < ApplicationController
  skip_before_filter :verify_authenticity_token, :only => [:create, :update]

  def index
    render_api_response current_user
  end

  def show
    user = User.find(params[:id])
    render_api_response user
  end

  def name_taken
    user = User.where(:username => params[:name]).first
    render_api_response({"result" => !user})
  end

  def set_username
    current_user.username = params[:name]
    current_user.save!
    render_api_response({"result" => !!current_user})
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

  def token_plans
    render_api_response User::TOKEN_SKUS
  end

  def add_tokens
    if params[:receipt] # From iOS
      data = Venice::Receipt.verify(params[:receipt]).to_h
      current_user.token_balance += User::TOKEN_SKUS[data[:product_id]][:tokens]
      current_user.save!
      render_api_response current_user
    else
      current_user.customer_object.set_default_card(params[:card_id])
      if current_user.customer_object.charge(params[:amount])
        current_user.token_balance += User::TOKEN_SKUS[params[:bid]][:tokens]
        current_user.save!
        render_api_response current_user
      end
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
