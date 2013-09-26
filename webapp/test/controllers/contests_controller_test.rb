require 'test_helper'

class ContestsControllerTest < ActionController::TestCase
  setup do
    setup_simple_market
    @public_contest_type = @market.contest_types.where("max_entries = 10 and buy_in = 100").first
    @user = create(:paid_user)
    sign_in @user
    @roster = Roster.generate(@user, @public_contest_type)
    @roster.submit!
  end

  test "invite to private contest" do
    assert_difference 'Invitation.count', 3 do
      post :create, :market_id => @market.id, 
          :contest_type_id => @roster.contest_type_id, 
          :invitees => "bob@my-jollies.com, fredrickson@withoutpajamas.uk.co\nwhoami@lostconsciousness.com"
    end
  end

  test "invite to public contest" do
    assert_difference 'Invitation.count', 3 do
      post :invite, :market_id => @market.id, :id => @roster.reload.contest.id, :invitees => "bob@my-jollies.com, fredrickson@withoutpajamas.uk.co\nwhoami@lostconsciousness.com"
    end
  end
end
