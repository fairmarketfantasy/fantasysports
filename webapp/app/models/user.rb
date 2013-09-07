class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable
  devise :omniauthable, :omniauth_providers => [:facebook]

  has_many :rosters, foreign_key: :owner_id
  has_many :contests, foreign_key: :owner
  has_one  :customer_object
  has_many :recipients


  def self.find_for_facebook_oauth(auth)
    user = User.where(uid: auth.uid, provider: auth.provider).first_or_create
    user.update_attributes(
      name:      auth.extra.raw_info.name,
      email:     auth.info.email,
      image_url: auth.info.image,
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

  def in_progress_roster
    rosters.where(:state => 'in_progress').first
  end

  def can_charge?(amount)
    return false unless customer_object
    return false if customer_object.balance - amount < 0
    return true
  end
end
