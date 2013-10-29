require 'test_helper'

class PlayersControllerTest < ActionController::TestCase
  setup do
    setup_simple_market
    @roster = create(:roster, :market => @market)
  end

  test "index action unauthenticated" do
    xhr :get, :index
    assert_response :unauthorized
  end

  test "index action authenticated" do
    sign_in create(:user)
    game = create(:game)
    autocomplete = "Michael Jor"
    xhr :get, :index, {autocomplete: "Michael Jor", team: 1, game: game.stats_id, in_contest: 3, roster_id: @roster.id}
    assert_response :success
    assert assigns(:players)
  end

  test "public" do
    setup_multi_day_market
    @market.started_at = Time.new
    @market.closed_at = Time.new + 2.days
    @market.state = nil
    @market.published_at = Time.new.yesterday
    @market.save
    @market.publish
    get :public
    assert resp_json['data'].length > 10
    assert resp_json['data'][0]['buy_price']
  end
end
