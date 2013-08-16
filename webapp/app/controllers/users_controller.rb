class UsersController < ApplicationController

  def show
    user = User.find(params[:id])
    render json: {data: [user]}
  end
end