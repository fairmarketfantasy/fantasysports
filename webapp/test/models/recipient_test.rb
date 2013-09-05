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
          recipient = Recipient.create({name: user.name, user: user, token: valid_account_token})
          recipient.errors[:user].wont_be_nil
        end
      end

      describe "no token param" do
        it "should raise arg error for no token" do
          lambda {
            Recipient.create({name: user.name, user: user})
          }.must_raise ArgumentError
        end
      end
    end

    describe "valid create" do
      it "should assign a stripe id" do
        r = Recipient.create({user: user, name: user.name, token: valid_account_token})
        r.id.wont_be_nil #record got saved
        r.stripe_id.wont_be_nil
      end
    end
  end
end
