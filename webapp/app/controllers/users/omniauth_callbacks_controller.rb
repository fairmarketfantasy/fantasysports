class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
   def facebook
    @user = User.find_for_facebook_oauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in @user, event: :authentication #this will throw if @user is not activated
      #if the user is not "confirmed", defined as a not-null confirmed_at timestamp, then this will fail
      # set_flash_message(:notice, :success, :kind => "Facebook") if is_navigational_format?
    else
      #this is what devise wants to do, but I'm not exactly sure why yet.
      session["devise.facebook_data"] = request.env["omniauth.auth"]
      redirect_to new_user_registration_url
    end
  end
end