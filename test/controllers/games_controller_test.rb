require 'test_helper'

class GamesControllerTest < ActionController::TestCase
  test "show page" do
    sign_in create(:user)
    game = create(:game)
    xhr :get, :show, id: game.stats_id
    assert_response :success
  end
end
