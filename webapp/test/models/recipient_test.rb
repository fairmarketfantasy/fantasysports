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
      it "should raise if user is unconfirmed" do
        lambda do
          Recipient.create({user: user}.merge(valid_account))
        end.must_raise(ArgumentError)
      end
    end

    describe "valid create" do
      before do
        user.stubs(:confirmed?).returns(true)
      end

      it "should assign a stripe id" do
        r = Recipient.create({user: user}.merge(valid_account))
        r.stripe_id.wont_be_nil
      end
    end
  end
end