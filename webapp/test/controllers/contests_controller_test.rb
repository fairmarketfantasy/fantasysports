require 'test_helper'

class ContestsControllerTest < ActionController::TestCase
  setup do
    setup_simple_market
    @public_contest_type = @market.contest_types.where("max_entries = 10 and buy_in = 100").first
    @user = create(:paid_user)
    @roster = Roster.generate(@user, @public_contest_type)
    @roster.submit!
  end

  test "invite to private contest" do
    sign_in @user
    assert_difference 'Contest.count', 1 do
      assert_difference 'Invitation.count', 3 do
        post :create, :market_id => @market.id, 
            :type => @public_contest_type.name,
            :buy_in => @public_contest_type.buy_in,
            :invitees => "bob@my-jollies.com, fredrickson@withoutpajamas.uk.co\nwhoami@lostconsciousness.com"
      end
    end
  end

  test "invite to public contest" do
    sign_in @user
    assert_difference 'Invitation.count', 3 do
      post :invite, :market_id => @market.id, :id => @roster.reload.contest.id, :invitees => "bob@my-jollies.com, fredrickson@withoutpajamas.uk.co\nwhoami@lostconsciousness.com"
    end
  end

  test "new user private contest invitation redirected" do
    contest = Contest.create_private_contest(
      :market_id => @market.id,
      :type => 'h2h',
      :buy_in => 100,
      :user_id => @user.id,
    )
    inv = nil
    assert_email_sent('bob@there.com') do
      assert_difference 'Invitation.count', 1 do
        inv = Invitation.for_contest(@user, 'bob@there.com', contest, 'HI BOB')
        assert inv
      end
    end
    get :join, :referral_code => inv.code, :contest_code => inv.private_contest.invitation_code
    assert(/autologin/ =~ response.headers["Location"])
    assert session["referrral_code"]
    assert session["contest_code"]
  end

  test "existing user accept private contest invitation" do
    sign_in @user
    @bob = create(:paid_user, :email => 'bob@there.com')
    contest = Contest.create_private_contest(
      :market_id => @market.id,
      :type => 'h2h',
      :buy_in => 100,
      :user_id => @user.id,
    )
    assert_email_sent('bob@there.com') do
      assert_difference 'Invitation.count', 0 do
        inv = Invitation.for_contest(@user, 'bob@there.com', contest, 'HI BOB')
        assert_nil inv
      end
    end
    get :join, :contest_code => contest.invitation_code
    assert_equal 302, response.code.to_i
    assert(/market\/\d+\/roster\/\d+/ =~ response.headers["Location"])
  end
end
