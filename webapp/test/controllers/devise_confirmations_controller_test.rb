require 'test_helper'

class Users::ConfirmationsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    user = create(:paid_user)
    sign_in user
  end

  test "post to users/confirmations" do
    assert_difference("ActionMailer::Base.deliveries.size", 1) do
      xhr :post, :create
    end
  end
end