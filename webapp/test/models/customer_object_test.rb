require 'test_helper'

class CustomerObjectTest < ActiveSupport::TestCase
  describe CustomerObject do

    describe ".create" do
      let(:user){ create(:user) }
      it "should be able to create" do
        CustomerObject.create({token: valid_card_token, user: user})
        user.reload.customer_object.stripe_id.wont_be_nil
      end
    end

    describe "transactions" do

      let(:user)            { create(:paid_user) }
      let(:customer_object) { user.customer_object }
      let(:amt)             { 600 }

      describe "#charge" do

        it "should get a Stripe::Charge instance back if successful" do
          resp = customer_object.charge(500)
          resp.must_be_instance_of Stripe::Charge
        end

        it "should invoke the #increase_balance method" do
          customer_object.expects(:increase_balance).with(amt, 'deposit')
          customer_object.charge(amt)
        end

        it "should raise if charge fails" do
          lambda{
            StripeMock.prepare_card_error(:card_declined)
            resp = user.customer_object.charge(20)
          }.must_raise Stripe::CardError
        end
      end

      describe "#increase_balance" do

        it "should increase by the amount" do
          assert_difference("CustomerObject.find(#{customer_object.id}).balance", amt) do
            assert_difference("TransactionRecord.count", 1) do
              customer_object.increase_balance(amt, 'deposit')
            end
          end
        end
      end

    end

  end
end
