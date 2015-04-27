require 'test_helper'

class Users::ConfirmationsControllerTest < ActionController::TestCase

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    user = create(:paid_user)
    sign_in user
  end

  test "post to users/confirmations" do
    assert_difference("ActionMailer::Base.deliveries.size", 1) do
      xhr :post, :create
    end
  end

  test "get to users/confirm with token" do
    user = create(:paid_user)
    raw, enc = Devise.token_generator.generate(user.class, :confirmation_token)
    user.confirmation_token   = enc
    user.confirmation_sent_at = Time.now.utc
    user.confirmed_at = nil
    user.save!

    xhr :get, :show, confirmation_token: raw
    user.reload
    assert user.confirmed?
    assert_equal @controller.current_user, user, "user is signed in"
  end
end