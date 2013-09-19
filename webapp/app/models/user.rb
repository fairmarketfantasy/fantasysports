class User < ActiveRecord::Base
  attr_accessible :name, :email, :provider, :uid, :unconfirmed_email, :image_url
  #attr_protected :admin, :email, :password
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

  attr_accessible :email, :password, :password_confirmation, :remember_me, :first_name, :last_name, :privacy, :accepted_privacy_at, :agreed_to_sync

  has_many :rosters, foreign_key: :owner_id
  has_many :contests, foreign_key: :owner_id
  has_one  :customer_object
  has_one  :recipient

  before_create :set_blank_name

  def set_blank_name
    self.name ||= ''
  end


  def self.find_for_facebook_oauth(auth)
    user = User.where(uid: auth.uid, provider: auth.provider).first_or_create
    user.name = auth.extra.raw_info.name
    user.email = auth.info.email
    user.image_url = auth.info.image.gsub('http', 'https')
    user.password = Devise.friendly_token[0,20]
    user.save!
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
