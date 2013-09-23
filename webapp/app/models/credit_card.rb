class CreditCard < ActiveRecord::Base

  #this class doesn't actually store and access the credit cards on stripe.
  #the purpose of this class is to store MD5 Hashes of CCs to prevent the same CC from
  #being used on multiple acccounts.

  #if you want to get information about a users cards, you would do that with CustomerObject#cards

  attr_accessible :customer_object_id, :card_number_hash, :deleted, :card_number, :token
  attr_accessor :card_number, :token

  belongs_to :customer_object

  before_validation :hash_card_number, :set_card_id, on: :create

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

  def set_card_id
    stripe_card = customer_object.stripe_object.cards.create({card: token})
    self.card_id = stripe_card.id
  end

end