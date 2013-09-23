require 'test_helper'

class Users::SessionsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @user = create :user
  end

  test "post to sessions create with the correct password" do
    xhr :post, :create, format: :json, user: {email: @user.email, password: "123456"}
    assert_equal @user, @controller.current_user
    assert_response :success
  end

  test "post to sessoins create with the wrong password" do
    xhr :post, :create, format: :json, user: {email: @user.email, password: "123"}
    assert_nil @controller.current_user
    resp = JSON.parse(response.body)
    assert_response :unauthorized
    assert_equal "Invalid email or password.", resp['error']
  end
end