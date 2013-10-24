require 'test_helper'

class CustomerObjectTest < ActiveSupport::TestCase
  describe CustomerObject do

    describe ".create" do
      let(:user){ create(:user) }
      it "should be able to create" do
        CustomerObject.create({user: user})
      end
    end

    describe "transactions" do

      let(:user)            { create(:paid_user) }
      let(:customer_object) { user.customer_object }
      let(:amt)             { 600 }

      describe "#charge" do
=begin
# TODO: write paypal tests. God dammit.
        it "should get a Paypal Payment instance back if successful" do
          resp = customer_object.charge(500)
          resp.must_be_instance_of PayPal::SDK::REST::Payment
        end

        it "should invoke the #increase_balance method" do
          customer_object.expects(:increase_balance).with(amt, 'deposit')
          customer_object.charge(amt)
        end
=end
      end

      describe "#increase_balance" do

        it "should increase by the amount" do
          assert_difference("customer_object.balance", amt) do
            assert_difference("TransactionRecord.count", 1) do
              customer_object.increase_balance(amt, 'deposit')
            end
          end
        end
      end

    end

  end
end
