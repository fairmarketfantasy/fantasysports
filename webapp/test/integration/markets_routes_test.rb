require 'test_helper'

class MarketRoutesTest < ActionDispatch::IntegrationTest

  test "markets index" do
    assert_routing({path: "/markets", method: :get}, {controller: "markets", action: "index"})
  end

  test "get markets contests" do
    m = markets(:one)
    assert_routing({path: "/markets/#{m.id}/contests", method: :get}, {controller: "markets", id: m.id.to_s, action: "contests"})
  end

  test "post markets contests" do
    m = markets(:one)
    assert_routing({path: "/markets/#{m.id}/contests", method: :post}, {controller: "markets", id: m.id.to_s, action: "contests"})
  end

end