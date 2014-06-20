require 'test_helper'

class SportsControllerTest < ActionController::TestCase
  setup do
    @user = create(:user)
    sign_in @user
  end

  test "should create prediction" do
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
    Prediction.create(
        user_id:         @user.id,
        stats_id:        'team_1',
        sport:           'FWC',
        game_stats_id:   'game_1',
        prediction_type: 'daily_wins',
        state:           'submitted',
        pt:              25
    )
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
