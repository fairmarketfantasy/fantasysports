class UsersController < ApplicationController
  skip_before_filter :authenticate_user!

  def show
    user = User.find(params[:id])
    render_api_response user
  end
end
