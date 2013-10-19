class CreditCard < ActiveRecord::Base
  attr_protected
  # Enforce generator usage
  private

  def self.create(opts)
    super
  end
  def self.create!(opts)
    super
  end
  def self.save(opts)
    super
  end
  def self.save!(opts)
    super
  end

  public

  def self.generate(customer_object, type, name, number, cvc, exp_month, exp_year)
    resp = PayPal::SDK::REST::CreditCard.new({
      :type => type,
      :number => number,
      :expire_month => Integer(exp_month),
      :expire_year => exp_year.to_s.length == 2 ? Integer("20" + exp_year.to_s) : exp_year,
      :first_name => name.split(' ')[0],
      :last_name => name.split(' ')[1],
    })
    resp.create
    if resp.state == "ok"
      c = CreditCard.new(
        :customer_object_id => customer_object.id,
        :paypal_card_id => resp.id,
        :card_type => resp.type,
        :obscured_number => resp.number,
        :expires => Time.new(resp.expire_year, resp.expire_month),
        :first_name => resp.first_name,
        :last_name => resp.last_name,
      )
      c.card_number = number
      c.save!
      customer_object.default_card = c
      customer_object.save!
    else
      raise "Paypal Card State not ok, was: " + resp["state"] + '. Response: ' + resp.to_json
    end
  end

  #this class is to store MD5 Hashes of CCs to prevent the same CC from
  #being used on multiple acccounts.

  #if you want to get information about a users cards, you would do that with CustomerObject#cards

  #attr_accessible :customer_object_id, :card_number_hash, :deleted, :card_number, :token, :obscured_number, :first_name, :last_name, :type, :expires
  attr_accessor :card_number, :token

  belongs_to :customer_object

  before_validation :hash_card_number, on: :create

  validates :customer_object_id, :card_number_hash, presence: true
  validate  :number_is_not_used

  STRIPE_TEST_NUMBERS = %w( 4242424242424242 4012888888881881 5555555555554444
                            5105105105105100 378282246310005  371449635398431
                            6011111111111117 6011000990139424 30569309025904
                            38520000023237   3530111333300000 3566002020360505)

  def number_is_not_used
    unless (is_a_stripe_test_number || self.deleted)
      if CreditCard.where.not(id: self.id).where(deleted: false, card_number_hash: card_number_hash).exists?
        errors.add(:base, "Card number has been used already.")
      end
    end
  end

  def hash_card_number
    self.card_number.gsub!(/\D+/, '')
    self.card_number_hash = Digest::MD5.hexdigest(card_number)
  end

  def is_a_stripe_test_number
    STRIPE_TEST_NUMBERS.include?(self.card_number.to_s)
  end

end
