require 'test_helper'

class Users::RegistrationsControllerTest < ActionController::TestCase

  setup do
    user = create(:paid_user)
    sign_in user
  end

  test "post to users/confirmations" do
    assert_difference("ActionMailer::Base.deliveries.size", 1) do
      xhr :post, :confirmations
    end
  end
end