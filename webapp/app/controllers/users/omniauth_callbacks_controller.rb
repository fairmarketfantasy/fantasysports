class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include Referrals

  def facebook
    @user = User.find_for_facebook_oauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in @user, event: :authentication #this will throw if @user is not activated
      #if the user is not "confirmed", defined as a not-null confirmed_at timestamp, then this will fail
      # set_flash_message(:notice, :success, :kind => "Facebook") if is_navigational_format?
      resp = handle_referrals(params[:sport])
      @redirect = resp[:redirect] || ''
      @flash = resp[:flash] || ''
      render '/users/create_close', :layout => false
    else
      render '/users/create_error', :layout => false
      #this is what devise wants to do, but I'm not exactly sure why yet.
      #session["devise.facebook_data"] = request.env["omniauth.auth"]
    end
  end

  def facebook_access_token

    @user = User.find_for_facebook_oauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in @user, event: :authentication #this will throw if @user is not activated
      render_api_response @user
    else
      render_api_response({:error => @user.errors.first.message })
    end
  end
end
