require 'test_helper'

class CardsControllerTest < ActionController::TestCase

  test "post to create without a CustomerObject" do
    user = create(:user) #doesn't have a customer object
    sign_in(user)
    assert_difference("CustomerObject.count", 1) do
      assert_difference("CreditCard.count", 1) do
        xhr :post, :create, {type: 'visa', name: 'bob hendrickson', number: '4242424242424242', cvc: '1234', exp_month: 12, exp_year: 15}
      end
    end
  end

  test "post to create when a user already has a customer object" do
    user = create(:paid_user) #already has a customer object
    sign_in(user)
    assert_no_difference("CustomerObject.count") do
      assert_difference("CreditCard.count", 1) do
        xhr :post, :create, {type: 'visa', name: 'bob hendrickson', number: '4242424242424242', cvc: '1234', exp_month: 12, exp_year: 15}
      end
    end
  end

  # test "delete to /cards/:id" do
  #   user = create(:paid_user)
  #   card_id = user.customer_object.default_card_id
  #   sign_in(user)
  #   user.customer_object.expects(:delete_a_card).with(card_id)
  #   xhr :delete, :destroy, {id: card_id}
  # end

end
