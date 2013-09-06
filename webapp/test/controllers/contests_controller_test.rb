require 'test_helper'

class ContestsControllerTest < ActionController::TestCase
  setup do
    user = create(:paid_user)
    sign_in user
    @contest = create(:contest, owner: user)
  end

  test "join action" do
    xhr :get, :join, {invitation_code: @contest.invitation_code}
    assert_response :success
  end
end
