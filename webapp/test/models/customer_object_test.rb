require 'test_helper'

class CustomerObjectTest < ActiveSupport::TestCase
  describe CustomerObject do

    describe ".create" do
      let(:user){ users(:two) }
      it "should be able to create" do
        resp = Stripe::Customer.create({
          description: "Customer for #{user.email}",
          card: {
            number:    "4242424242424242",
            exp_month: 10,
            exp_year:  2015,
            cvc:       123,
            name:      "Jack Johnson"
          }
        })
        CustomerObject.create({stripe_id: resp.id, user_id: user.id})
        user.reload.customer_object.stripe_id.must_equal resp.id
      end
    end

    describe "#charge" do
      let(:user){ users(:one) }
      it "should get a Stripe::Charge instance back if successful" do
        resp = user.customer_object.charge(500)
        resp.must_be_instance_of Stripe::Charge
      end

      it "should raise if charge fails" do
        lambda{
          resp = user.customer_object.charge(20)
        }.must_raise Stripe::InvalidRequestError
      end
    end

    describe "#balance" do
      let(:user){ users(:one) }
      it "should return a numeric" do
        user.customer_object.account_balance.must_be_kind_of Numeric
      end
    end
  end
end
