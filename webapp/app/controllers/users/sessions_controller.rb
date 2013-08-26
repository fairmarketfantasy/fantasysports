class Users::SessionsController < Devise::SessionsController


  def create
    self.resource = warden.authenticate!(auth_options)
    sign_in(resource_name, resource)
    render json: UserSerializer.new(current_user, scope: current_user)
  end

  def sign_in_params
    devise_parameter_sanitizer.sanitize(:sign_in)
  end
end