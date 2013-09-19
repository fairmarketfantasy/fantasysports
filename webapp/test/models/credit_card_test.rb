require 'test_helper'

class CreditCardTest < ActiveSupport::TestCase

  describe CreditCard do

    let(:card_number) { "1234-5678-7899-9122" }
    let(:new_credit_card) { build(:credit_card, card_number: card_number,
                                                customer_object_id: 1) }

    describe "on create hash the card_number" do
      after(:each) do
        new_credit_card.destroy
      end

      subject do
        new_credit_card.save!
        new_credit_card
      end

      it "will hash the card number" do
        subject.card_number_hash.wont_equal card_number
      end
    end

    describe ".number_is_used" do
      before(:all) do
        create( :credit_card,
                card_number: card_number,
                customer_object_id: 1)
      end

      subject { new_credit_card }

      it "will return false if the number has been used" do
        subject.valid?.must_equal false
        subject.errors.full_messages.must_include "Card number has been used already."
      end
    end

    describe "exclude stripe test numbers from validation" do
      let(:stripe_number) { "4242424242424242" }
      before(:all) do
        create( :credit_card,
                customer_object_id: 1,
                card_number: stripe_number)
      end

      subject { build(:credit_card, customer_object_id: 1, card_number: stripe_number) }

      it "should be able to save another card with a stripe test number" do
        subject.save!.must_equal true
      end

    end

  end
end