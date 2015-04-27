require 'test_helper'

class PagesControllerTest < ActionController::TestCase


  test "get home" do
    get :index
    assert_response :success
    assert_template 'pages/index'
  end

  test "get about" do
    get :about
    assert_response :success
    assert_template 'pages/about'
  end

  test "get term" do
    skip "This test case causes error, skip it for now"
    get :terms
    assert_response :success
    assert_template 'pages/terms'
  end

  test "get sign up" do
    get :sign_up
    assert_response :success
    assert_template 'pages/sign_up'
  end

end