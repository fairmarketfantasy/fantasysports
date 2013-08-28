require 'test_helper'

class AccountControllerTest < ActionController::TestCase
  setup do
    user = create(:user)
    create(:good_recipient, user: user, legal_name: user.name)
    sign_in(user)
  end

  test "recipients endpoint" do
    xhr :get, :recipients
    assert_response :success
  end
end
