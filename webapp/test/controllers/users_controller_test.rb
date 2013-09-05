require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  setup do
    @user = create(:user)
    @co   = customer_objects(:one)
    @amount = 5000
  end

  test "show" do
    xhr :get, :show, {id: @user.id}
    assert_response :success
  end

  test "add_money" do
    sign_in(@user)
    @controller.current_user.stubs(:customer_object).returns(@co)
    assert_difference("CustomerObject.find(#{@co.id}).balance", @amount) do
      xhr :post, :add_money, {amount: @amount}
    end
    assert_response :success
  end
end
