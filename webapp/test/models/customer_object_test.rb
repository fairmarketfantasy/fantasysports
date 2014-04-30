require 'test_helper'

class CustomerObjectTest < ActiveSupport::TestCase
  describe CustomerObject do

    describe ".create" do
      let(:user){ create(:user) }
      it "should be able to create" do
        CustomerObject.create({user: user})
      end
    end

    describe "transactions" do

      let(:user)            { create(:paid_user) }
      let(:customer_object) { user.customer_object }
      let(:amt)             { 600 }

      describe "#charge" do
=begin
# TODO: write paypal tests. God dammit.
        it "should get a Paypal Payment instance back if successful" do
          resp = customer_object.charge(500)
          resp.must_be_instance_of PayPal::SDK::REST::Payment
        end

        it "should invoke the #increase_balance method" do
          customer_object.expects(:increase_balance).with(amt, 'deposit')
          customer_object.charge(amt)
        end
=end
      end

      describe "#increase_balance" do

        it "should increase by the amount" do
          assert_difference("customer_object.balance", amt) do
            assert_difference("TransactionRecord.count", 1) do
              customer_object.increase_account_balance(amt, :event => 'deposit')
            end
          end
        end
      end

    end

  end

  test "monthly accounting" do
    c = create(:user).customer_object
    c.update_attributes(:monthly_winnings => 245000, :monthly_contest_entries => 45)
    assert_equal c.taxed_net_monthly_winnings, 72500
    assert_difference "c.reload.monthly_winnings", -245000 do
      assert_difference "c.reload.balance",  72500 - 1000 do # -1000 for this month's activation
        c.do_monthly_accounting!
      end
    end

    assert_equal c.net_monthly_winnings, 0
    assert_equal c.monthly_contest_entries, 0
    assert c.is_active?
    assert c.last_activated_at
  end

  test "monthly accounting when balance is less then -50 FB" do
    c = create(:user).customer_object
    c.update_attributes(:monthly_winnings => 45, :monthly_contest_entries => 45)
    assert_difference "c.reload.monthly_winnings", -45 do
      assert_difference "c.reload.balance", 0 do # -1000 for this month's activation
        c.do_monthly_accounting!
      end
    end

    assert_equal c.reload.net_monthly_winnings, -5000.0
    assert_equal c.reload.monthly_contest_entries, 5
    assert !c.is_active?
    assert !c.last_activated_at
  end

  test "monthly accounting when balance is between -50 and 0 FB" do
    c = create(:user).customer_object
    c.update_attributes(:monthly_winnings => 1000, :monthly_contest_entries => 2)
    assert_difference "c.reload.monthly_winnings", -1000 do
      assert_difference "c.reload.balance", 0 do # -1000 for this month's activation
        c.do_monthly_accounting!
      end
    end

    assert_equal c.net_monthly_winnings, -1000
    assert_equal c.monthly_contest_entries, 1
    assert !c.is_active?
    assert !c.last_activated_at
  end

  test "user activation" do
    u = create(:user)
    assert !u.customer_object.is_active?
    u.customer_object.increase_account_balance(1000, :event => 'deposit')
    assert_difference "u.customer_object.reload.balance", -1000 do
      u.customer_object.do_monthly_activation!
    end
    assert u.customer_object.is_active?
  end

  test "taxed winnings" do
    c = create(:user).customer_object
    c.update_attributes(:monthly_winnings => 245000, :monthly_contest_entries => 45)
    assert_equal c.taxed_net_monthly_winnings, 72500
  end

  test "double activate not double charged" do
    u = create(:user)
    assert !u.customer_object.is_active?
    u.customer_object.increase_account_balance(1000, :event => 'deposit')
    assert_difference "u.customer_object.reload.balance", -1000 do
      u.customer_object.do_monthly_activation!
      u.customer_object.do_monthly_activation!
    end
    assert u.customer_object.is_active?
  end
end
