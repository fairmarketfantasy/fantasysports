class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception



  before_filter :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_up) { |u| u.permit(:email, :password, :password_confirmation, :name) }
    devise_parameter_sanitizer.for(:sign_in) { |u| u.permit(:email, :password) }
  end

  def render_api_response(data, opts = {}) # TODO: handle pagination?
    opts[:json] = data
    if data.respond_to?(:to_a) && data.class != Hash
      opts[:serializer] = ApiArraySerializer
    end
    render opts
  end
end
