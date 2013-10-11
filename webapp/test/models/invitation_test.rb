require 'test_helper'

class InvitationTest < ActiveSupport::TestCase
  test "unpaid user has invitation accepted" do
    setup_simple_market
    u1 = create(:user)
    contest = Contest.create_private_contest(
      :market_id => @market.id,
      :type => 'h2h',
      :buy_in => 100,
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
    Invitation.redeem(u2, inv.code)
    assert u1.customer_object
    assert u1.customer_object.balance = Invitation::FREE_USER_REFERRAL_PAYOUT
  end

  test "paid user redemptions" do
    user = create(:paid_user)
    user2 = create(:user, :inviter => user)
    assert_difference "user.customer_object.reload.balance", Invitation::PAID_USER_REFERRAL_PAYOUT do
      Invitation.redeem_paid(user2)
      Invitation.redeem_paid(user2)
    end
  end
end
