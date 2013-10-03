class Users::RegistrationsController < Devise::RegistrationsController
  prepend_before_filter :require_no_authentication, :only => [ :new, :create, :cancel ]
  # POST /resource
  def sign_up_from_html
    build_resource(sign_up_params)

    if resource.save
      if resource.active_for_authentication?
        sign_up(resource_name, resource)
        render :json => resource, status: :created
      else
        expire_session_data_after_sign_in!
        render :json => {error: resource.errors.full_messages.first}, status: :unprocessable_entity
      end
    else
      clean_up_passwords resource
      render :json => {error: resource.errors.full_messages.first}, status: :unprocessable_entity
    end
  end

  def sign_up_from_json
    r = build_resource(params[:user])
    user = User.where(:email => r.email).first
    # Allow posting the same info again
    if user && user.valid_password?(r.password)
      r = user
    end
    if r.save
      render_api_response r.reload
    else
      render :json => {:error => resource.errors.values.join(', ')}, :status => :unprocessable_entity
    end
  end

  def create
    respond_to do |format|
      format.html {
        super
      }
      format.json {
        if request.headers['content-type'] == 'application/json'
          sign_up_from_json
        else
          sign_up_from_html
        end
      }
    end
  end

  # Almost copied from: https://github.com/plataformatec/devise/blob/692175b897a45786e67c38c7b48f230084934652/app/controllers/devise/registrations_controller.rb#L39
  # STOLEN FROM ANOTHER PROJECT, Most of this may not be relevant
  def update
    # devise_parameter_sanitizer.for(:account_update)
    # account_update_params
    prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)
    prev_confirmed_email   = resource.email

    change_unconfirmed_email if prev_unconfirmed_email

    if resource.update_without_password(account_update_params)
      sign_in resource_name, resource, :bypass => true
      render json: resource.reload, status: :ok
    else
      clean_up_passwords(resource)
      render json: {error: resource.errors.full_messages.first}, status: :unprocessable_entity
    end
    # image_s3_path = params[:user].delete(:image_s3_path)

    # self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
    # prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email )

    # if resource.update_with_password(resource_params)
    #   if is_navigational_format?
    #     flash_key = update_needs_confirmation?(resource, prev_unconfirmed_email) ?
    #       :update_needs_confirmation : :updated
    #     set_flash_message :notice, flash_key
    #   end
    #   sign_in resource_name, resource, :bypass => true
    #   #respond_with resource, :location => after_update_path_for(resource)
    # else
    #   clean_up_passwords resource
    #   #respond_with resource
    # end

    # current_user.reload

    # if image_s3_path
    #   if img = current_user.photo
    #     # TODO: Delete the current photo
    #   end
    #   current_user.photo = Image.create!(:uuid => UUID.new.generate, :s3_path => image_s3_path)
    #   current_user.save!
    # end
    # respond_to do |format|
    #   format.html {
    #     respond_with resource, :location => after_update_path_for(resource)
    #   }
    #   format.json {
    #     render :status => 200, :partial => 'common/user_or_contact', :locals => {:user_or_contact => current_user}
    #   }
    # end
  end

  protected

    #when this gets changed, devise fires off an email to the new email address
    def change_unconfirmed_email
      resource.unconfirmed_email = account_update_params[:email]
    end
end
