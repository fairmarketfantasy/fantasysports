require 'test_helper'

class RostersControllerTest < ActionController::TestCase
  setup do
    setup_simple_market
    sign_in(create(:paid_user))
    @contest_type = create(:contest_type)
  end

  test "post /rosters" do
    assert_difference("Roster.count", 1) do
      xhr :post, :create, {market_id: @market.id, contest_type_id: @contest_type.id, buy_in: 2}
    end
    assert_response :success
  end

end
