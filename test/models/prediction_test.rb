require 'test_helper'

class PredictionTest < ActiveSupport::TestCase
  test "should process predictions" do
    game = Game.create(
        game_day:         Time.now,
        game_time:        Time.now,
        home_team:        '3bbe1893-home',
        away_team:        '3bbe1893-away',
        stats_id:         '3bbe1893-game',
        season_type:      'REG',
        sport_id:         899,
        home_team_pt:     25,
        away_team_pt:     35,
        home_team_status: 1,
        away_team_status: 1,
        status:           'scheduled'
    )
    Prediction.create(
        user_id:         1,
        stats_id:        '3bbe1893-home',
        sport:           899,
        game_stats_id:   '3bbe1893-game',
        prediction_type: 'daily_wins',
        state:           'submitted',
        pt:              25
    )

    Prediction.process_prediction(game, 'daily_wins')

    prediction         = Prediction.last
    transaction_record = TransactionRecord.last

    assert_equal 'finished', prediction.state
    assert_equal true,       game.checked
    assert_equal 1,          transaction_record.user_id
    assert_equal 13.5,       transaction_record.amount
    assert_equal "dead_heat_daily_wins_prediction", transaction_record.event
  end

  test "should process dead heat" do
    game = Game.create(
        game_day:         Time.now,
        game_time:        Time.now,
        home_team:        '3bbe1893-home',
        away_team:        '3bbe1893-away',
        stats_id:         '3bbe1893-game',
        season_type:      'REG',
        sport_id:         899,
        home_team_pt:     25,
        away_team_pt:     35,
        home_team_status: 1,
        away_team_status: 1,
        status:           'scheduled'
    )
    Prediction.create(
        user_id:         1,
        stats_id:        '3bbe1893-home',
        sport:           899,
        game_stats_id:   '3bbe1893-game',
        prediction_type: 'daily_wins',
        state:           'submitted',
        pt:              25
    )

    Prediction.process_prediction(game, 'daily_wins')

    prediction = Prediction.last

    assert_equal 'Dead heat', prediction.result
    assert_equal 13.5,        prediction.award.to_d
  end

  test "should process win" do
    game = Game.create(
        game_day:         Time.now,
        game_time:        Time.now,
        home_team:        '3bbe1893-home',
        away_team:        '3bbe1893-away',
        stats_id:         '3bbe1893-game',
        season_type:      'REG',
        sport_id:         899,
        home_team_pt:     25,
        away_team_pt:     35,
        home_team_status: 1,
        away_team_status: 0,
        status:           'scheduled'
    )
    Prediction.create(
        user_id:         1,
        stats_id:        '3bbe1893-home',
        sport:           899,
        game_stats_id:   '3bbe1893-game',
        prediction_type: 'daily_wins',
        state:           'submitted',
        pt:              25
    )

    Prediction.process_prediction(game, 'daily_wins')

    prediction = Prediction.last

    assert_equal 'Win', prediction.result
    assert_equal 25,    prediction.award.to_d
  end

  test "should process lose" do
    game = Game.create(
        game_day:         Time.now,
        game_time:        Time.now,
        home_team:        '3bbe1893-home',
        away_team:        '3bbe1893-away',
        stats_id:         '3bbe1893-game',
        season_type:      'REG',
        sport_id:         899,
        home_team_pt:     25,
        away_team_pt:     35,
        home_team_status: 1,
        away_team_status: 3,
        status:           'scheduled'
    )
    Prediction.create(
        user_id:         1,
        stats_id:        '3bbe1893-home',
        sport:           899,
        game_stats_id:   '3bbe1893-game',
        prediction_type: 'daily_wins',
        state:           'submitted',
        pt:              25
    )

    Prediction.process_prediction(game, 'daily_wins')

    prediction = Prediction.last

    assert_equal 'Lose', prediction.result
    assert_equal 0,      prediction.award.to_d
  end
end
