require 'test_helper'

class RecipientTest < ActiveSupport::TestCase

  describe Recipient do
    let(:user) { 
      user = create(:user) 
      user.customer_object = create(:customer_object, user: user)
      user
    }

    describe "invalid .create" do

      describe "un-confirmed user" do
        before do
          user.stubs(:confirmed?).returns(false)
        end
        it "should populate user errors if user is unconfirmed" do
          recipient = Recipient.create({user: user, paypal_email: user.email, paypal_email_confirmation: user.email})
          recipient.errors[:user].wont_be_nil
        end
      end

    end

    describe "valid create" do
      it "should be created" do
        r = Recipient.create({user: user, paypal_email: user.email, paypal_email_confirmation: user.email })
        r.id.wont_be_nil #record got saved
      end
    end
  end
end
