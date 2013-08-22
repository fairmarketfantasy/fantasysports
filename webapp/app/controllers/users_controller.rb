class UsersController < ApplicationController

  def show
    user = User.find(params[:id])
    render_api_response user
  end
end
