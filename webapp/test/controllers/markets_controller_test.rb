require 'test_helper'

class MarketsControllerTest < ActionController::TestCase
  test "index" do
    xhr :get, :index
    assert_response :success
    assert assigns(:markets)
    assert_template 'markets/index'
  end

  # test "get :id/contests" do
  #   m = markets(:one)
  #   xhr :get, :contests, {id: m.id}
  # end

  test "post :id/contests unauthenticated" do
    m = markets(:one)
    assert_no_difference("Contest.count", 1) do
      xhr :post, :contests, {id: m.id, emails: ["yodawg@yo.com", "royale@cheese.com"], type: "194"}
    end
    assert_response :unauthorized
  end

  test "post :id/contests authenticated" do
    m = markets(:one)
    sign_in users(:one)
    assert_difference("Contest.count", 1) do
      xhr :post, :contests, {id: m.id, emails: ["yodawg@yo.com"], buy_in: 40, type: "194"}
    end
    assert_response :success
  end
end
