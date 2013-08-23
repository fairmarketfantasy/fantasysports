require 'test_helper'

class ContestsControllerTest < ActionController::TestCase
  def setup
    sign_in(users(:one))
  end

  test "join action" do
    c = contests(:one)
    xhr :get, :join, {invitation_code: c.invitation_code}
    assert_response :success
  end
end
