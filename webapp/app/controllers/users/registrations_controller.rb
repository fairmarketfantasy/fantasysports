class Users::RegistrationsController < Devise::RegistrationsController
  prepend_before_filter :require_no_authentication, :only => [ :new, :create, :cancel ]
  # POST /resource
  def sign_up_from_html
    build_resource(sign_up_params)

    if resource.save
      if resource.active_for_authentication?
        sign_up(resource_name, resource)
        render_api_response resource, handle_referrals.merge({status: :created})
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
      opts = handle_referrals
      render_api_response r.reload, opts
    else
      render :json => {:error => resource.errors.values.join(', ')}, :status => :unprocessable_entity
    end
  end

  def handle_referrals
    resp = {}
    if session[:referral_code]
      Invitation.redeem(current_user, session[:referral_code])
      session[:referral_code] = nil
    end
    if session[:contest_code]
      contest = Contest.where(:invitation_code => session[:contest_code]).first
      if contest.private?
        raise HttpException.new(403, "You already have a roster in this contest") if contest.rosters.map(&:owner_id).include?(current_user.id)
        roster = Roster.generate(current_user, contest.contest_type)
        roster.update_attribute(:contest_id, contest.id)
      else
        roster = Roster.generate(current_user, contest.contest_type)
      end
      session[:contest_code] = nil
      resp.merge! redirect: "/market/#{contest.market_id}/roster/#{roster.id}"
    end
    resp
  end

  def create
    begin
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
      Eventing.report(current_user, 'new_user')
    rescue StandardError => e
      if e.message =~ /username.*already exists/
        raise HttpException.new(422, "That username is taken. Choose another one")
      end
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
