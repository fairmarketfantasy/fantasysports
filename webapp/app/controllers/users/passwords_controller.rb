class Users::PasswordsController < Devise::PasswordsController

  # GET /users/password/edit?reset_password_token=abcdef
  def edit
    self.resource = resource_class.new
    resource.reset_password_token = params[:reset_password_token]
    render 'users/reset_password', layout: 'landing'
  end

  # PUT /users/password
  def update
    self.resource = resource_class.reset_password_by_token(resource_params)

    if resource.errors.empty?
      resource.unlock_access! if unlockable?(resource)
      flash_message = resource.active_for_authentication? ? :updated : :updated_not_active
      sign_in(resource_name, resource)
      render json: resource
    else
      render json: {error: resource.errors.full_messages.first}, status: :unprocessable_entity
    end
  end
end