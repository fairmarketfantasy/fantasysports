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
    user = User.find_by(email: auth.info.email)
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

  def in_progress_roster
    rosters.where(:state => 'in_progress').first
  end

  def can_charge?(amount)
    return false unless customer_object
    return false if customer_object.balance - amount < 0
    return true
  end
end
