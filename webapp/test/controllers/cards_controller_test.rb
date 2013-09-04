require 'test_helper'

class CardsControllerTest < ActionController::TestCase

  test "post to create without a CustomerObject" do
    user = create(:user) #doesn't have a customer object
    sign_in(user)
    assert_difference("CustomerObject.count", 1) do
      xhr :post, :create, {token: valid_card_token}
    end
  end

  test "post to create when a user already has a customer object" do
    user = create(:user) #already has a customer object
    sign_in(user)
    assert_difference("CustomerObject.count", 1) do
      xhr :post, :create, {token: valid_card_token}
    end
  end

end