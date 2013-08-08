require 'test_helper'

class Devise::RegistrationsControllerTest < ActionController::TestCase

  def setup
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  test "post to users" do
    assert_difference("User.count", 1) do
      xhr :post, :create, user: {name: "Terry P", email: "auseremail@gmail.com", password: "1234abcd", password_confirmation: "1234abcd"}
    end
  end
end