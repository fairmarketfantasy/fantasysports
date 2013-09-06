require 'test_helper'

class MarketTest < ActiveSupport::TestCase

  # create a market that has three games at three different times.
  # roster 1 buys some players. get the price of one of the players.
  # game 1 starts, update market
  # assert that the players available are only from the 2 remaining games
  # assert that the prices
  # roster 2 buys some players. repeat process
  # test "players pulled out of markets when game happens" do
  test "lock players TODO unfinished" do
    setup_multi_day_market
    @market.publish

    #find a $10 contest_type in the market's contest types
    contest_type = @market.contest_types.where(:buy_in => 10).first

    #create some roster and have it buy things
    roster = create(:roster, :market => @market, :contest_type => contest_type)
    assert roster.purchasable_players.length == 36, "should be 36 players"
    roster.fill_randomly
    #buy more players randomly
    10.times {
      roster = create(:roster, :market => @market, :contest_type => contest_type)
      roster.fill_randomly
    }

    #open the market. ensure that shadow bets are removed
    @market.open
    @market.reload
    assert @market.shadow_bets == 0, "no shadow bets after open"
    assert @market.state == "opened"

    #print out the current prices
    roster = create(:roster, :market => @market, :contest_type => contest_type)
    prices1 = roster.purchasable_players.collect(&:buy_price)
    # puts "prices before game 1: ", prices1

    #now make a game happen by setting the locked_at to the past for the first 18 players
    @market.market_players.first(18).each do |mp|
      mp.locked_at = Time.now - 1000
    end
    @market.lock_players

    # puts game0.stats_id
    # assert game0.length == 1 && game0[0].id == @games[0].id, "expected game #{@games[0].id}, found game #{game0.id}"
  end




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
