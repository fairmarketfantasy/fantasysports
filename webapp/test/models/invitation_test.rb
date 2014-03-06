require 'test_helper'

class InvitationTest < ActiveSupport::TestCase
  test "unpaid user has invitation accepted" do
    setup_simple_market
    u1 = create(:user)
    contest = Contest.create_private_contest(
      :market_id => @market.id,
      :type => '27 H2H',
      :buy_in => 1000,
      :user_id => u1.id,
    )
    inv = nil
    assert_email_sent('bob@there.com') do
      assert_difference 'Invitation.count', 1 do
        inv = Invitation.for_contest(u1, 'bob@there.com', contest, 'HI BOB')
        assert inv
      end
    end
    u2 = create(:user)
    assert_difference "TransactionRecord.count", 1 do
      Invitation.redeem(u2, inv.code)
    end
    assert u1.customer_object
    assert u1.customer_object.balance = Invitation::FREE_USER_REFERRAL_PAYOUT
  end

  test "paid user redemptions" do
    user = create(:paid_user)
    user2 = create(:user, :inviter => user)
    assert_difference "TransactionRecord.count", 4 do
      assert_difference "user.customer_object.reload.balance", Invitation::PAID_USER_REFERRAL_PAYOUT do
        Invitation.redeem_paid(user2)
        Invitation.redeem_paid(user2)
      end
    end
    assert_equal Invitation::PAID_USER_REFERRAL_PAYOUT, user2.reload.customer_object.balance
  end

  test "Unsubscribe stops emails from sending" do
    setup_simple_market
    u1 = create(:user)
    contest = Contest.create_private_contest(
      :market_id => @market.id,
      :type => '27 H2H',
      :buy_in => 1000,
      :user_id => u1.id,
    )
    inv = nil
    email = 'bob@there.com'
    EmailUnsubscribe.create(:email => email, :email_type => 'all')
    assert_email_not_sent do
      assert_difference 'Invitation.count', 1 do
        inv = Invitation.for_contest(u1, 'bob@there.com', contest, 'HI BOB')
        assert inv
      end
    end

  end
end
