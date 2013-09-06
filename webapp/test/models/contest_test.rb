require 'test_helper'

class ContestTest < ActiveSupport::TestCase
  describe Contest do

    before(:all) do
      setup_simple_market
      @user = create(:paid_user)
      @contest = Contest.new(owner:     @user,
                             contest_type:  create(:contest_type),
                             buy_in:    10,
                             market_id: @market.id)
    end

    describe "create" do
      it "should create a contest for the owner" do
        assert_difference("@user.contests.count", 1) do
          @contest.save!
        end
      end
    end

    describe "#create_owners_roster!" do
      it "should create a roster for the owner" do
        assert_difference("@user.rosters.count", 1) do
          @contest.save!
        end
      end
    end

    describe "#invite" do
      it "should send an email to the invitee" do
        assert_difference("ActionMailer::Base.deliveries.size", 1) do
          @contest.invite("yodawg@gmail.com")
        end
      end
    end

  end
end
