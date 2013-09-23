class Users::SessionsController < Devise::SessionsController

  def create
    self.resource = warden.authenticate!(auth_options)
    sign_in(resource_name, resource)
    render json: UserSerializer.new(current_user, scope: current_user)
  end

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    redirect_to root_url
  end

  def sign_in_params
    devise_parameter_sanitizer.sanitize(:sign_in)
  end
end