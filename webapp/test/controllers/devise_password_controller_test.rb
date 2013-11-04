require 'test_helper'

class Users::PasswordsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @user = create :user
    @user.send_reset_password_instructions
  end

  test "put to update password" do
    raw, enc = Devise.token_generator.generate(@user.class, :reset_password_token)
    @user.reset_password_token = enc
    @user.save!
    xhr :put, :update, user: {password: '123456', password_confirmation: "123456", reset_password_token: raw}
    assert_equal @user, @controller.current_user
    assert_response :success
  end
end