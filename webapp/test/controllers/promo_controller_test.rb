require 'test_helper'

class PromoControllerTest < ActionController::TestCase
  promo = Promo.create(:code => 'top-secret', :valid_until => Time.new.tomorrow, :cents => 1000)
  test "create drops cookie" do
    post :create, :code => promo.code
    assert_equal 200, response.code.to_i
    assert session["promo_code"]
  end
end
