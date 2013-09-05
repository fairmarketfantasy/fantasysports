require 'test_helper'

class MarketsControllerTest < ActionController::TestCase

  setup do
    setup_simple_market
    @ct = create(:contest_type)
  end

  test "index" do
    xhr :get, :index
    assert_response :success
  end

  # test "get :id/contests" do
  #   m = markets(:one)
  #   xhr :get, :contests, {id: m.id}
  # end

  test "post :id/contests unauthenticated" do
    m = @market
    assert_no_difference("Contest.count") do
      xhr :post, :contests, {id: m.id, emails: ["yodawg@yo.com", "royale@cheese.com"], contest_type_id: @ct.id, buy_in: 2}
    end
    assert_response :unauthorized
  end

  test "post :id/contests authenticated" do
    m = @market
    sign_in users(:one)
    assert_difference("Contest.count", 1) do
      xhr :post, :contests, {id: m.id, emails: ["yodawg@yo.com"], buy_in: 40, contest_type_id: @ct.id, buy_in: 2}
    end
    assert_response :success
  end

end
