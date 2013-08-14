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

  # test "post :id/contests" do
  #   m = markets(:one)
  #   xhr :post, :contests, {id: m.id}
  # end
end
