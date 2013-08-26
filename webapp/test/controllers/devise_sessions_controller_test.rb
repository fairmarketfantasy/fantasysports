require 'test_helper'

class Users::SessionsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @user = create :user
  end

  test "post to sessoins create with the correct password" do
    xhr :post, :create, user: {email: @user.email, password: "123456"}
    assert_equal @user, @controller.current_user
  end

  test "post to sessoins create with the wrong password" do
    xhr :post, :create, user: {email: @user.email, password: "123"}
    assert_nil @controller.current_user
  end
end