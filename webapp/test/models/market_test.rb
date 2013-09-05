require 'test_helper'

class MarketTest < ActiveSupport::TestCase

  test "publish open and close" do
    setup_new_market
    assert @market.players.length == 0
    @market = @market.publish
    assert !@market.nil?, "should not be null"
    assert @market.players.length > 0, "should be players"
    assert @market.contest_types.length > 0
    assert @market.total_bets > 0
    assert @market.shadow_bets > 0

    #open the market. should remove the shadow bets
    @market = @market.open
    # puts "market after open: #{@market.inspect}"
    assert @market.shadow_bets == 0, "shadow bets 0"
    assert @market.total_bets == 0, "bets 0"
    assert @market.state = "opened", "state is opened"

    #close market
    @market = @market.close
    assert @market.state == 'closed', "should be closed"
  end

  describe Market do

    describe "scopes" do
      describe "opened after" do
        it "should produce valid SQL" do
          assert_nothing_raised do
            Market.opened_after(Time.now).inspect
          end
        end
      end

      describe "closed after" do
        it "should produce valid SQL" do
          assert_nothing_raised do
            Market.closed_after(Time.now).inspect
          end
        end
      end

      describe "chain them all together" do
        it "should produce valid SQL" do
          assert_nothing_raised do
            Market.opened_after(Time.now).closed_after(Time.now).page(1).order('closed_at asc').inspect
          end
        end
      end
    end

  end
end
