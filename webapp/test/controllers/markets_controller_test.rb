require 'test_helper'

class MarketsControllerTest < ActionController::TestCase
  test "index" do
    xhr :get, :index
    assert_response :success
    assert assigns(:markets)
  end
end
