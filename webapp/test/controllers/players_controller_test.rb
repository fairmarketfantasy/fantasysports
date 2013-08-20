require 'test_helper'

class PlayersControllerTest < ActionController::TestCase
  test "index action unauthenticated" do
    xhr :get, :index
    assert_response :unauthorized
  end

  test "index action authenticated" do
    sign_in users(:one)
    ac = "Michael Jor"
    xhr :get, :index, {autocomplete: "Michael Jor", team: 1, game: '8c0bce5a', in_contest: 3}
    assert_response :success
    assert assigns(:players)
  end
end
