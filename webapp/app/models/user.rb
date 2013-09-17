class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :oauth2_providable, 
         :oauth2_password_grantable,
         :oauth2_refresh_token_grantable,
         :oauth2_authorization_code_grantable,
         :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable
  devise :omniauthable, :omniauth_providers => [:facebook]

  has_many :rosters, foreign_key: :owner_id
  has_many :contests, foreign_key: :owner_id
  has_one  :customer_object
  has_one  :recipient


  def self.find_for_facebook_oauth(auth)
    user = User.where(uid: auth.uid, provider: auth.provider).first_or_create
    user.update_attributes(
      name:      auth.extra.raw_info.name,
      email:     auth.info.email,
      image_url: auth.info.image.gsub('http', 'https'),
      password:  Devise.friendly_token[0,20]
    )
    user
  end

  def confirmation_required?
    false
  end

  def email
    self[:email].blank? ? self.unconfirmed_email : self[:email]
  end

  def image_url
    if self[:image_url]
      self[:image_url]
    else
      gravatar_id = Digest::MD5.hexdigest(email.downcase)
      "https://www.gravatar.com/avatar/#{gravatar_id}"
    end
  end

  def in_progress_roster
    rosters.where(:state => 'in_progress').first
  end

  def can_charge?(amount)
    return true if amount == 0
    return false unless customer_object
    return false if customer_object.balance - amount < 0
    return true
  end
end
