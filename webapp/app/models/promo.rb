class PromoRedemption < ActiveRecord::Base
  attr_protected
  belongs_to :user
  belongs_to :promo
end
class Promo < ActiveRecord::Base
  attr_protected
  has_many :promo_redemptions

  def redeem!(user)
    self.class.transaction do
      redeemed = PromoRedemption.where(:user_id => user.id, :promo_id => self.id).first
      raise HttpException.new(403, "You already redeemed that code!") if redeemed
      raise HttpException.new(403, "That code is no longer valid!") if self.valid_until < Time.new
      PromoRedemption.create!(:user_id => user.id, :promo_id => self.id)
      if self.cents > 0
        SYSTEM_USER.charge(self.cents, :event => 'promo', :promo_id=> self.id)
        user.payout(self.cents, :event => "promo", :promo_id => self.id)
      end
    end
  end
end
