require 'test_helper'

class SportsControllerTest < ActionController::TestCase
  test "should create prediction" do
    sign_in create(:user)

    params = {
      game_stats_id:   'game_1',
      predictable_id:  'team_2',
      prediction_type: 'daily_wins',
      sport:           'FWC'
    }

    xhr :post, :create_prediction, params

    assert_response :success
    assert_equal 'daily wins prediction submitted successfully!', json_response['msg']
  end

  test "should not create prediction" do
    sign_in create(:user)

    params = {
        game_stats_id:   'game_1',
        predictable_id:  'team_1', #Such prediction exists
        prediction_type: 'daily_wins',
        sport:           'FWC'
    }

    xhr :post, :create_prediction, params

    assert_response :unprocessable_entity
    assert_equal 'daily wins prediction creation failed!', json_response['error']
  end

  def json_response
    ActiveSupport::JSON.decode @response.body
  end
end
