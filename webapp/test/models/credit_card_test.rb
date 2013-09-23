require 'test_helper'

class CreditCardTest < ActiveSupport::TestCase

  describe CreditCard do

    let(:card_number) { "1234-5678-7899-9122" }
    let(:user)        { create(:paid_user) }
    let(:new_credit_card) { build(:credit_card, card_number: card_number,
                                                token: valid_card_token,
                                                customer_object: user.customer_object) }

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
                token: valid_card_token,
                customer_object: user.customer_object)
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
                card_number: stripe_number,
                token: valid_card_token,
                customer_object: user.customer_object)
      end

      subject { build(:credit_card, customer_object: user.customer_object, token: valid_card_token, card_number: stripe_number) }

      it "should be able to save another card with a stripe test number" do
        subject.save!.must_equal true
      end

      describe "setting the deleted flag to true" do
        before(:all) do
          3.times do
            create( :credit_card,
                    card_number: stripe_number,
                    token: valid_card_token,
                    customer_object: user.customer_object)
          end
        end

        subject { user.customer_object.credit_cards.last }

        it "should be able to set the deleted flag to true" do
          subject.deleted = true
          subject.save!.must_equal true
          subject.reload.deleted.must_equal true
        end

      end

    end

  end
end