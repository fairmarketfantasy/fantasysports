require 'test_helper'

class Users::RegistrationsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  test "post to users" do
    assert_difference("User.count", 1) do
      xhr :post, :create, format: :json, user: {name: "Terry P", email: "auseremail@gmail.com", password: "1234abcd", password_confirmation: "1234abcd"}
      assert_response :created
    end
  end

  test "post to users with failure" do
    assert_no_difference("User.count") do
      xhr :post, :create, format: :json, user: {name: "Terry P", email: ""}
      assert_response :unprocessable_entity
      resp = JSON.parse(response.body)
      assert_equal "Email can't be blank", resp['error']
    end
  end
end