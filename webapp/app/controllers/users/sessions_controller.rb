class Users::SessionsController < Devise::SessionsController
  include Referrals

  def create
    self.resource = warden.authenticate! scope: resource_name, recall: "#{controller_path}#sign_in_failure"
    sign_in resource_name, resource
    render_api_response current_user, handle_referrals
    #render json: UserSerializer.new(current_user, scope: current_user)
  end

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    redirect_to root_url
  end

  def sign_in_params
    devise_parameter_sanitizer.sanitize(:sign_in)
  end

  def sign_in_failure
    render json: { error: 'login failed: invalid username or password' }, status: :unauthorized
  end
end
