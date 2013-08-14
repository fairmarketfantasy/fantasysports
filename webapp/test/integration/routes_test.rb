require 'test_helper'

class RoutesTest < ActionDispatch::IntegrationTest

  test "home route" do
    assert_routing({path: "/", method: :get}, { controller: "pages", action: "index" })
  end

  test "terms route" do
    assert_routing({path: "/terms", method: :get}, { controller: "pages", action: "terms" })
  end

  test "about route" do
    assert_routing({path: "/about", method: :get}, { controller: "pages", action: "about" })
  end

  test "sign_up route" do
    assert_routing({path: "/sign_up", method: :get}, { controller: "pages", action: "sign_up" })
  end

  test "post to /users route" do
    assert_routing({path: "/users", method: :post}, {controller: "devise/registrations", action: "create"})
  end

  test "get to /users/:id route" do
    assert_routing({path: "/users/1", method: :get}, {controller: "users", action: "show", id: '1'})
  end

  test "players index" do
    assert_routing({path: "/players", method: :get}, {controller: "players", action: "index"})
  end

  test "games show" do
    g = games(:one)
    assert_routing({path: "/games/#{g.stats_id}", method: :get}, {controller: "games", action: "show", id: g.stats_id})
  end

  test "markets index" do
    assert_routing({path: "/markets", method: :get}, {controller: "markets", action: "index"})
  end

end