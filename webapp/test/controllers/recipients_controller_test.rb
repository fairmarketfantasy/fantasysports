require 'test_helper'

class RecipientsControllerTest < ActionController::TestCase
  setup do
    @user = create(:user)
    sign_in(@user)
  end

  test "index endpoint" do
    xhr :get, :index
    assert_response :success
  end

  test "creating a recipient" do
    assert_difference("Recipient.count", 1) do
      xhr :post, :create, {recipient: {name: @user.name, token: valid_account_token}}
      assert_response :success
    end
  end
end
