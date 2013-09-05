require 'test_helper'

class ContestTest < ActiveSupport::TestCase
  describe Contest do

    before(:all) do
      setup_simple_market
    end
    let(:u) { users(:one) }
    let(:m) { @market }
    let(:c) { Contest.new(owner:     u,
                          contest_type:  create(:contest_type),
                          buy_in:    10,
                          market_id: m.id) }
    describe "create" do
      it "should create a contest for the owner" do
        assert_difference("User.find(#{u.id}).contests.count", 1) do
          c.save!
        end
      end
    end

    describe "#create_owners_roster!" do
      it "should create a roster for the owner" do
        assert_difference("User.find(#{u.id}).rosters.count", 1) do
          c.save!
        end
      end
    end

    describe "#invite" do
      it "should send an email to the invitee" do
        assert_difference("ActionMailer::Base.deliveries.size", 1) do
          c = contests(:one)
          c.invite("yodawg@gmail.com")
        end
      end
    end

  end
end
