class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery

  rescue_from 'HttpException', :with => :http_exception_handler

  before_filter :configure_permitted_parameters, if: :devise_controller?
  before_filter :authenticate_user!

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:account_update) { |u| u.permit(:email, :password, :password_confirmation, :current_password, :name, :username, :avatar) }
    devise_parameter_sanitizer.for(:sign_up)        { |u| u.permit(:email, :password, :password_confirmation, :name, :username) }
    devise_parameter_sanitizer.for(:sign_in)        { |u| u.permit(:email, :password) }
  end

  def render_api_response(data, opts = {}) # TODO: handle pagination?
    if data.respond_to?(:to_a) && data.class != Hash
      opts[:serializer] = ApiArraySerializer
    end
    if opts[:redirect]
      response.headers['X-CLIENT-REDIRECT'] = opts.delete(:redirect)
    end
    opts[:json] = data
    render opts
  end

  def http_exception_handler(e)
    render :status => e.code, :json => {error: e.message}
  end

  after_filter  :set_csrf_cookie_for_ng

  def set_csrf_cookie_for_ng
      cookies['XSRF-TOKEN'] = form_authenticity_token if protect_against_forgery?
  end

  def verified_request?
    form_authenticity_token == request.headers['HTTP_X_XSRF_TOKEN'] || super
  end
end
