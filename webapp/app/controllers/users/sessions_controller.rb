class Users::SessionsController < Devise::SessionsController
  include Referrals

  def create
    self.resource = warden.authenticate! scope: resource_name, recall: "#{controller_path}#sign_in_failure"
    sign_in resource_name, resource
    delete_broken_rosters(current_user)
    render_api_response current_user, handle_referrals(sport: params[:sport], category: params[:category])
    #render json: UserSerializer.new(current_user, scope: current_user)
  end

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))

    respond_to do |format|
      format.json  { render :json => {} }
      format.html { redirect_to root_url }
    end
  end

  def sign_in_params
    devise_parameter_sanitizer.sanitize(:sign_in)
  end

  def sign_in_failure
    render json: { error: 'login failed: invalid username or password' }, status: :unauthorized
  end

  private

  # hot fix until market loosing will be fixed
  def delete_broken_rosters(user)
    user.rosters.each { |roster| roster.destroy if roster.market.nil? }
  end
end
