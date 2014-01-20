require 'test_helper'

class CardsControllerTest < ActionController::TestCase

  test "activate with card payment" do
    user = create(:paid_user) #already has a customer object
    sign_in(user)
    @customer_object = user.customer_object
    @customer_object.update_attribute(:balance, 1000)
    card = user.customer_object.credit_cards.first
    NetworkMerchants.stubs(:charge_finalize).returns(true)
    assert_difference('@customer_object.reload.balance', -1000) do
      xhr :post, :charge_redirect_url, 'token-id' => 'blah', :callback => 'callme'
    end
    assert user.customer_object.is_active?

  end

  test "post to create when a user already has a customer object" do
    o = stub(:id => 12,
            :type       => 'visa',
            :number => '**2039',
            :expire_year         => 2016,
            :expire_month        => 12,
            :state           => 'ok',
            :first_name      => 'Merry',
            :last_name       => 'Hobag',
            :create          => true)
    PayPal::SDK::REST::CreditCard.stubs(:new).returns(o)
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
