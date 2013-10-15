require 'test_helper'

class Users::RegistrationsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  test "post to users" do
    assert_difference("User.count", 1) do
      xhr :post, :create, format: :json, user: {name: "Terry P", email: "auseremail@gmail.com", password: "1234abcd", password_confirmation: "1234abcd"}
      assert_response :created
    end
  end

  test "post to users with failure" do
    assert_no_difference("User.count") do
      xhr :post, :create, format: :json, user: {name: "Terry P", email: ""}
      assert_response :unprocessable_entity
      resp = JSON.parse(response.body)
      assert_equal "Email can't be blank", resp['error']
    end
  end

  test "put to users" do
    user = create(:user)
    sign_in(user)
    new_name = "New Name"
    xhr :post, :update, format: :json, id: user.id, user: {name: new_name}
    assert_response :success
    resp = JSON.parse(response.body)
    assert_equal new_name, resp["name"]
  end

  test "put to users with password changed" do
    user = create(:user)
    original_password = user.encrypted_password
    sign_in(user)
    xhr :post, :update, format: :json, id: user.id, user: {current_password: "123456", password: "aNewP4assW0rd", password_confirmation: "aNewP4assW0rd"}
    assert_response :success
    user.reload
    refute_equal original_password, user.encrypted_password
  end

  test "new user private contest invitation post signup" do
    setup_simple_market
    @user = create(:paid_user)
    contest = Contest.create_private_contest(
      :market_id => @market.id,
      :type => 'h2h',
      :buy_in => 100,
      :user_id => @user.id,
    )
    inv = Invitation.for_contest(@user, 'bob@there.com', contest, 'HI BOB')

    request.session[:referral_code] = inv.code
    request.session[:contest_code] = contest.invitation_code
    assert_difference '@user.customer_object.reload.balance', Invitation::FREE_USER_REFERRAL_PAYOUT do
      xhr :post, :create, format: :json, user: {name: "Terry P", email: "bob@there.com", password: "1234abcd", password_confirmation: "1234abcd"}
    end
    assert response.headers['X-CLIENT-REDIRECT']
  end

end
