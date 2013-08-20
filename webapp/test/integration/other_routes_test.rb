require 'test_helper'

class OtherRoutesTest < ActionDispatch::IntegrationTest

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

  test "join_contest/" do
    code = "123"
    assert_equal join_contest_path(code), "/join_contest/#{code}"
    assert_routing({path: "/join_contest/#{code}", method: :get}, {controller: "contests", action: "join", invitation_code: code})
  end

  test "contests/:id/join" do
    c = contests(:one)
    assert_routing({path: "/contests/#{c.id}/join", method: :post}, {controller: "contests", action: "join", id: c.id.to_s})
  end

  test "webhooks route" do
    assert_routing({path: "/webhooks", method: :post}, { controller: "webhooks", action: "new" })
  end
end