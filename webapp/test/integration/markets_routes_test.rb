require 'test_helper'

class MarketRoutesTest < ActionDispatch::IntegrationTest

  setup do
    setup_simple_market
  end

  test "markets index" do
    assert_routing({path: "/markets", method: :get}, {controller: "markets", action: "index"})
  end

  test "get markets contests" do
    m = @market
    assert_routing({path: "/markets/#{m.id}/contests", method: :get}, {controller: "markets", id: m.id.to_s, action: "contests"})
  end

  test "post markets contests" do
    m = @market
    assert_routing({path: "/markets/#{m.id}/contests", method: :post}, {controller: "markets", id: m.id.to_s, action: "contests"})
  end

end