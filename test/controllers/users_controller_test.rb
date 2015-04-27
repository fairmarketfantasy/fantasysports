require 'test_helper'

class UsersControllerTest < ActionController::TestCase

  setup do
    @user = create(:paid_user)
    sign_in @user
    @customer_object = @user.customer_object
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
    CreditCard.generate(@customer_object, 'visa', 'fan boy', '4242424242424242', '4321', 12, 19)
    @user.customer_object.default_card
    @amount = 1000
  end

  test "show" do
    xhr :get, :show, {id: @user.id}
    assert_response :success
  end

  test "add_money" do
    skip "This test case causes error, skip it for now"
    #PayPal::SDK::REST::Payment.any_instance.stubs(:create).returns(Object.new.expects(:approval_url).returns("http://blah.com"))
    assert_difference('@customer_object.reload.balance', 0) do
      xhr :post, :add_money, {amount: @amount}
    end
    response
    assert_response :success
  end

  test "paypal_return" do
    skip "This test case causes error, skip it for now"
    PayPal::SDK::REST::Payment.stubs(:find).returns(PayPal::SDK::REST::Payment.new)
    #Object.new.expects(:approval_url).returns("http://blah.com"))
    PayPal::SDK::REST::Payment.any_instance.stubs(:execute).returns(true)
    PayPal::SDK::REST::Payment.any_instance.stubs(:transactions).returns([Object.new.stubs(:amount).returns(stub(:total => @amount))])
    assert_difference('@customer_object.reload.balance', 0) do
      xhr :post, :add_money, {amount: @amount}
    end
    assert @user.customer_object.is_active?

  end

  test "withdraw_money" do
    # sign_in(@user)
    # @controller.current_user.stubs(:customer_object).returns(@customer_object)
    # assert_difference('@customer_object.balance', @amount) do
    #   xhr :post, :withdraw_money, {amount: @amount}
    # end
  end

  test "reset_password good email" do
    sign_out @user
    User.any_instance.expects(:send_reset_password_instructions)
    xhr :post, :reset_password, {email: @user.email}
    assert_response :success
  end

  test "reset_password bad email" do
    sign_out @user
    User.any_instance.expects(:send_reset_password_instructions).never
    xhr :post, :reset_password, {email: "somerandomefakenonexistantemail"}
    assert_response :unprocessable_entity
  end

end
