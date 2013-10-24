require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  setup do
    @user = create(:paid_user)
    sign_in @user
    @customer_object = @user.customer_object
    CreditCard.generate(@customer_object, 'visa', 'fan boy', '4242424242424242', '4321', 12, 19)
    @user.customer_object.default_card
    @amount = 5000
  end

  test "show" do
    xhr :get, :show, {id: @user.id}
    assert_response :success
  end

  test "add_money" do
    assert_difference('@customer_object.reload.balance', @amount) do
      xhr :post, :add_money, {amount: @amount}
    end
    assert_response :success
  end

  test "withdraw_money" do
    # sign_in(@user)
    # @controller.current_user.stubs(:customer_object).returns(@customer_object)
    # assert_difference('@customer_object.balance', @amount) do
    #   xhr :post, :withdraw_money, {amount: @amount}
    # end
  end

  test "add tokens" do
    sku_id = '1000'
    sku    = User::TOKEN_SKUS[sku_id]
    assert_difference('@user.reload.token_balance', sku[:tokens]) do
      xhr :post, :add_tokens, {product_id: sku_id}
    end

  end

end
