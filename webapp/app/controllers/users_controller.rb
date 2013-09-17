class UsersController < ApplicationController
  skip_before_filter :authenticate_user!

  def show
    user = User.find(params[:id])
    render_api_response user
  end

  def add_money
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    current_user.customer_object.set_default_card(params[:card_id])
    if current_user.customer_object.charge(params[:amount])
      render_api_response current_user
    end
  end

  def withdraw_money
    authenticate_user!
    unless params[:amount]
      render json: {error: "Must supply an amount"}, status: :unprocessable_entity and return
    end
    if current_user.recipient.transfer(params[:amount])
      render_api_response current_user.reload
    end
  end

  def create
    respond_to do |format|••
      format.html {•
        super•
      }
      format.json {
        r = build_resource
        user = User.where(:email => r.email).first
        # Allow posting the same info again
        if user && user.valid_password?(r.password)
          r = user
        end
        if r.save
           Canonicalizer.update_contacts_to_user(r)
           render :status => 200, :partial => 'common/user_or_contact', :locals => {:user_or_contact => r.reload}
        else
          render :json => {:error => resource.errors.values.join(', ')}, :status => :unprocessable_entity
        end
      } 
    end 
  end

  # Almost copied from: https://github.com/plataformatec/devise/blob/692175b897a45786e67c38c7b48f230084934652/app/controllers/devise/registrations_controller.rb#L39
  # STOLEN FROM ANOTHER PROJECT, Most of this may not be relevant
  def update
    image_s3_path = params[:user].delete(:image_s3_path)

    self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
    prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email )

    if resource.update_with_password(resource_params)
      if is_navigational_format?
        flash_key = update_needs_confirmation?(resource, prev_unconfirmed_email) ?
          :update_needs_confirmation : :updated
        set_flash_message :notice, flash_key
      end
      sign_in resource_name, resource, :bypass => true
      #respond_with resource, :location => after_update_path_for(resource)
    else
      clean_up_passwords resource
      #respond_with resource
    end

    current_user.reload

    if image_s3_path
      if img = current_user.photo
        # TODO: Delete the current photo
      end
      current_user.photo = Image.create!(:uuid => UUID.new.generate, :s3_path => image_s3_path)
      current_user.save!
    end
    respond_to do |format|
      format.html {
        respond_with resource, :location => after_update_path_for(resource)
      }
      format.json {
        render :status => 200, :partial => 'common/user_or_contact', :locals => {:user_or_contact => current_user}
      }
    end
  end
end
