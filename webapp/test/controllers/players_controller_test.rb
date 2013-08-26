require 'test_helper'

class PlayersControllerTest < ActionController::TestCase
  setup do
    setup_simple_market
  end
  test "index action unauthenticated" do
    xhr :get, :index
    assert_response :unauthorized
  end

  test "index action authenticated" do
    sign_in users(:one)
    m = @market
    ac = "Michael Jor"
    xhr :get, :index, {autocomplete: "Michael Jor", team: 1, game: '8c0bce5a', in_contest: 3, market_id: m.id}
    assert_response :success
    assert assigns(:players)
  end
end
