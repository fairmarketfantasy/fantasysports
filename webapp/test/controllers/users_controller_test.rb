require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  setup do
    @user = create(:paid_user)
    @customer_object = @user.customer_object
    @amount = 5000
  end

  test "show" do
    xhr :get, :show, {id: @user.id}
    assert_response :success
  end

  test "add_money" do
    sign_in(@user)
    @controller.current_user.stubs(:customer_object).returns(@customer_object)
    assert_difference('@customer_object.balance', @amount) do
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
end
