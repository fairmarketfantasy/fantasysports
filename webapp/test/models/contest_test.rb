require 'test_helper'

class ContestTest < ActiveSupport::TestCase
  describe Contest do

    let(:u) { users(:one) }
    let(:m) { markets(:one) }
    let(:c) { Contest.new(owner:     u,
                          type:      "194",
                          buy_in:    10,
                          market_id: m.id,
                          invitees:  ["yodawg@xhibit.com"]) }
    describe "create" do
      it "should create a contest for the owner" do
        assert_difference("User.find(#{u.id}).contests.count", 1) do
          c.save!
        end
      end
    end

    describe "#create_owners_roster!" do
      it "should create a roster for the owner" do
        assert_difference("User.find(#{u.id}).contest_rosters.count", 1) do
          c.save!
        end
      end
    end

    describe "#invite_emails" do
      it "should send an email to the invitee" do
        assert_difference("ActionMailer::Base.deliveries.size", 1) do
          c.send(:invite_emails)
        end
      end
    end

  end
end
