require 'test_helper'

class RecipientTest < ActiveSupport::TestCase

  describe Recipient do
    let(:user)       { create(:user) }
    let(:valid_account) do
      {
        country:     'US',
        routing:     '110000000',
        account_num: '000123456789'
      }
    end

    describe "invalid .create" do

      describe "confirmed user" do
        before do
          user.stubs(:confirmed?).returns(false)
        end
        it "should populate user errors if user is unconfirmed" do
          recipient = Recipient.create({user: user}.merge(valid_account))
          recipient.errors[:user].wont_be_nil
        end
      end

      describe "strip API error" do
        it "should send back some stripe api errors" do
          recipient = Recipient.create({user: user, routing: '123', account_num: '1234'})
          #TODO, fix this in Recipient.create inside rescue block
          refute recipient.valid
        end
      end
    end

    describe "valid create" do

      it "should assign a stripe id" do
        r = Recipient.create({user: user}.merge(valid_account))
        r.stripe_id.wont_be_nil
      end
    end
  end
end