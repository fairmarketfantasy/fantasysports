require 'test_helper'

class PromoTest < ActiveSupport::TestCase
  before do
    @promo = Promo.create(:code => 'top-secret', :valid_until => Time.new.tomorrow, :cents => 1000)
    @user = create(:user)
  end

  test "redeem valid" do
    assert_difference('@user.customer_object.reload.balance', 1000) do
      @promo.redeem!(@user)
    end
  end

  test "double redeem" do
    assert_difference('@user.customer_object.reload.balance', 1000) do
      @promo.redeem!(@user)
    end
    assert_raises HttpException do
      @promo.redeem!(@user)
    end
  end

  test "redeem invalid" do
    promo = Promo.create(:code => 'top-secret2', :valid_until => Time.new.yesterday, :cents => 1000)
    assert_raises HttpException do
      promo.redeem!(@user)
    end
  end
  # test "the truth" do
  #   assert true
  # end
end
