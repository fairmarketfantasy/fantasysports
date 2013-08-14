class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable
  has_many :contest_rosters
  devise :omniauthable, :omniauth_providers => [:facebook]


  def self.find_for_facebook_oauth(auth)
    user = User.find_by(provider: auth.provider, uid: auth.uid)
    unless user
      user = User.create( name:     auth.extra.raw_info.name,
                          provider: auth.provider,
                          uid:      auth.uid,
                          email:    auth.info.email,
                          password: Devise.friendly_token[0,20])
    end
    user
  end

  def confirmation_required?
    false
  end

  def email
    self[:email].blank? ? self.unconfirmed_email : self[:email]
  end
end
