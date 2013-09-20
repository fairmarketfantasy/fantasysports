require 'test_helper'

class ContestTest < ActiveSupport::TestCase

  test "payday" do
    setup_simple_market
    contest_type = @market.contest_types.where("max_entries = 2 and buy_in = 200").first
    refute_nil contest_type

    user1 = create(:user)
    user1.customer_object = create(:customer_object, user: user1)
    user2 = create(:user)
    user2.customer_object = create(:customer_object, user: user2)
    
    roster1 = Roster.generate(user1, contest_type).submit!
    roster2 = Roster.generate(user2, contest_type).submit!
    #make sure rosters are in same contest
    assert_equal roster1.contest, roster2.contest

    roster1.contest_rank = 1
    roster2.contest_rank = 2
    roster1.save!
    roster2.save!

    roster1.contest.payday!
    user1.reload
    user2.reload
    assert user1.customer_object.balance > user2.customer_object.balance

    roster1.reload
    roster2.reload
    assert roster1.amount_paid > 0
    assert_equal 0,  roster2.amount_paid
    assert roster1.paid_at && roster2.paid_at
    assert roster1.state == 'finished'
    assert roster2.state == 'finished'
  end

  #test auxillary functions
  test "payday auxillary functions" do
    contest_type = create(:contest_type, :payout_structure => [5,4,3,2,1].to_json)
    ranks = [1,1,3,3,5,5,5,8,9,10]
    rank_payment = contest_type.rank_payment(ranks)
    expected = {1 => 9, 3 => 5, 5 => 1}
    assert_equal expected, rank_payment

    rosters = [create(:roster, :contest_rank => 1),
               create(:roster, :contest_rank => 2),
               create(:roster, :contest_rank => 2),
               create(:roster, :contest_rank => 4)]
    by_rank = Contest._rosters_by_rank(rosters)
    assert_equal by_rank.length, 3
    assert_equal by_rank[2].length, 2
  end

  describe Contest do

    before(:all) do
      setup_simple_market
      @user = create(:paid_user)
      @contest = Contest.new(owner:     @user,
                             contest_type:  create(:contest_type),
                             buy_in:    10,
                             market_id: @market.id)
    end

    describe "#make_private" do
      it "should create a contest for the owner" do
        assert_difference("@user.contests.count", 1) do
          @contest.save!
        end
      end
    end

    describe "#create_owners_roster!" do
      it "should create a roster for the owner" do
        assert_difference("@user.rosters.count", 1) do
          @contest.make_private
        end
      end
    end

    describe "#invite" do
      it "should send an email to the invitee" do
        assert_difference("ActionMailer::Base.deliveries.size", 1) do
          @contest.make_private
          @contest.invite("yodawg@gmail.com")
        end
      end
    end

  end
end
