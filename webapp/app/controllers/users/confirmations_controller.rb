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
end
