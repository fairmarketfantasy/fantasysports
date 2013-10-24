require 'test_helper'

class MarketsControllerTest < ActionController::TestCase

  setup do
    setup_simple_market
    @market.started_at = Time.new - 4.days
    @market.save
    setup_simple_market
    @contest_type = create(:contest_type)
    @user = create(:user)
    @user.customer_object = create(:customer_object, user: @user)
  end

  test "index" do
    xhr :get, :index
    assert_response :success
  end

end
