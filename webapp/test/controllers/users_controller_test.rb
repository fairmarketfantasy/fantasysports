require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  test "show" do
    u = users(:one)
    xhr :get, :show, {id: u.id}
    assert_response :success
  end
end
