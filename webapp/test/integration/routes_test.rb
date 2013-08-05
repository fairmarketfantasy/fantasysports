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

end