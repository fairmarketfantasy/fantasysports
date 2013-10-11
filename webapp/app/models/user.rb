class User < ActiveRecord::Base
  TOKEN_SKUS = {
    '1000' => {:tokens => 1000, :cost => 100},
    '5000' => {:tokens => 5000, :cost => 500},
    '10000' => {:tokens => 10000, :cost => 1000},
  }
  #attr_protected :admin, :email, :password
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :oauth2_providable, 
         :oauth2_facebook_grantable,
         :oauth2_password_grantable,
         :oauth2_refresh_token_grantable,
         :oauth2_authorization_code_grantable,
         :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable
  devise :omniauthable, :omniauth_providers => [:facebook, :facebook_access_token]

  attr_accessible :name, :username, :provider, :uid, :fb_token, :unconfirmed_email, :image_url, :takes_tokens,
      :email, :password, :password_confirmation, :remember_me, :first_name,
      :last_name, :privacy, :accepted_privacy_at, :agreed_to_sync, :inviter_id

  has_many :rosters, foreign_key: :owner_id
  has_many :contests, foreign_key: :owner_id
  has_many :push_devices
  has_one  :customer_object
  has_one  :recipient
  belongs_to :inviter, :class_name => 'User'

  before_create :set_blank_name
  before_create :award_tokens

  def set_blank_name
    self.name ||= ''
  end

  def award_tokens
    self.token_balance = 1000
  end


  def self.find_for_facebook_oauth(auth)
    Rails.logger.debug(auth.pretty_inspect)
    user = User.find_by(email: auth.info.email) || User.where(uid: auth.uid, provider: auth.provider, fb_token: auth.credentials.token).first_or_create
    user.email = auth.info.email
    user.fb_token = auth.credentials.token
    user.name = auth.extra.raw_info.name
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

  def can_charge?(amount, charge_tokens = false)
    return true if amount == 0
    if charge_tokens
      return false if amount > self.token_balance
    else
      return false unless customer_object
      return false if amount > customer_object.balance
    end
    return true
  end

  def charge(amount, use_tokens, opts = {})
    if use_tokens
      ActiveRecord::Base.transaction do
        self.reload
        raise HttpException.new(409, "You don't have enough FanFrees for that.") if amount > self.token_balance
        self.token_balance -= amount
        TransactionRecord.create!(:user => self, :event => opts[:event], :amount => -amount, :roster_id => opts[:roster_id], :contest_id => opts[:contest_id],:invitation_id => opts[:invitation_id], :is_tokens => use_tokens)
        self.save
      end
    else
      self.customer_object.decrease_balance(amount, opts[:event], opts[:roster_id], opts[:contest_id], opts[:invitation_id])
    end
  end

  #def increase_balance(amount, event, roster_id = nil, contest_id = nil, invitation_id= nil)
  def payout(amount, use_tokens, opts)
    if use_tokens
      ActiveRecord::Base.transaction do
        self.reload
        self.token_balance += amount
        TransactionRecord.create!(:user => self, :event => opts[:event], :amount => amount, :roster_id => opts[:roster_id], :contest_id => opts[:contest_id], :invitation_id => opts[:invitation_id], :referred_id => opts[:referred_id], :is_tokens => use_tokens)
        self.save
      end
    else
      if self.customer_object.nil?
        CustomerObject.create!(:user_id => self.id)
      end
      self.reload.customer_object.increase_balance(amount, opts[:event], opts[:roster_id], opts[:contest_id], opts[:invitation_id], opts[:referred_id])
    end
  end
end
