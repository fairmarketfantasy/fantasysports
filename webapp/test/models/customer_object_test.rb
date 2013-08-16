require 'test_helper'

class CustomerObjectTest < ActiveSupport::TestCase
  describe CustomerObject do

    describe ".create" do
      let(:user){ users(:two) }
      it "should be able to create" do
        card =  {
                  number:    "4242424242424242",
                  exp_month: 10,
                  exp_year:  2015,
                  cvc:       123,
                  name:      "Jack Johnson"
                }
        CustomerObject.create({card: card, user: user})
        user.reload.customer_object.stripe_id.wont_be_nil
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
  end
end
