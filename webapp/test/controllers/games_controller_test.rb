require 'test_helper'

class GamesControllerTest < ActionController::TestCase
  test "the truth" do
    sign_in users(:one)
    g = games(:one)
    xhr :get, :show, id: g.stats_id
    assert_response :success
  end
end
