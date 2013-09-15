class Users::RegistrationsController < Devise::RegistrationsController
  prepend_before_filter :require_no_authentication, :only => [ :new, :create, :cancel ]
  # POST /resource
  def create
    build_resource(sign_up_params)

    if resource.save
      if resource.active_for_authentication?
        sign_up(resource_name, resource)
        render :json => resource, status: :created
      else
        expire_session_data_after_sign_in!
        render :json => {error: resource.errors.full_messages}, status: :ok
      end
    else
      clean_up_passwords resource
      render :json => {error: resource.errors.full_messages}, status: :ok
    end
  end

end