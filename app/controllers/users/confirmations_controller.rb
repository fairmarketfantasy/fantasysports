class Users::ConfirmationsController < Devise::ConfirmationsController

  # POST /resource/confirmation
  def create
    if self.resource = current_user #user is logged in
      current_user.send_confirmation_instructions
    else #user is not logged in
      self.resource = resource_class.send_confirmation_instructions(resource_params)
    end

    if successfully_sent?(resource)
      render json: {message: "Success check your email: #{resource.email} for a confirmation link."}
    else
      render json: {errors: ["Oops, something went wrong."]}
    end
  end

  # GET /resource/confirmation?confirmation_token=abcdef
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])
    if resource.errors.empty?
      if Devise.allow_insecure_sign_in_after_confirmation
        sign_in(resource_name, resource)
      else
        set_flash_message(:notice, :confirmed) if is_navigational_format?
      end
      render '/users/confirmed_reload', :layout => false
    else
      render json: {errors: ["Oops, something went wrong."]}
    end
  end

end
