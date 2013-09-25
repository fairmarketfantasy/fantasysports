require 'test_helper'

class MarketRoutesTest < ActionDispatch::IntegrationTest

  setup do
    setup_simple_market
  end

  test "markets index" do
    assert_routing({path: "/markets", method: :get}, {controller: "markets", action: "index"})
  end

end