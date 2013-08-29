require 'test_helper'

class RecipientTest < ActiveSupport::TestCase

  describe Recipient do
    let(:user)       { create(:user) }
    let(:valid_account) do
      {
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
          recipient = Recipient.create({user: user, legal_name: user.name}.merge(valid_account))
          recipient.errors[:user].wont_be_nil
        end
      end

      describe "strip API errors" do
        it "should send back routing number too short error" do
          recipient = Recipient.create({user: user, legal_name: user.name, routing: '123', account_num: '1234'})
          #TODO, fix this in Recipient.create inside rescue block
          assert_equal "Routing number must have 9 digits", recipient.errors[:base].first
        end
      end
    end

    describe "valid create" do

      it "should assign a stripe id" do
        r = Recipient.create({user: user, legal_name: user.name}.merge(valid_account))
        r.stripe_id.wont_be_nil
      end
    end
  end
end