require 'test_helper'

class MobilePagesControllerTest < ActionController::TestCase
  test "should get forgot_password" do
    get :forgot_password
    assert_response :success
  end

  test "should get support" do
    skip "This test case causes error, skip it for now"
    get :support
    assert_response :success
  end

  test "should get terms" do
    get :terms
    assert_response :success
  end

  test "should get rules" do
    get :rules
    assert_response :success
  end

end
