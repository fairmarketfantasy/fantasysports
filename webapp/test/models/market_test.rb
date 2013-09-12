require 'test_helper'

class MarketTest < ActiveSupport::TestCase

  #
  test "close" do
    setup_simple_market
    #put 3 rosters public h2h and 3 in a private h2h
    contest_type = @market.contest_types.where("buy_in = 10 and max_entries = 2").first
    refute_nil contest_type
    3.times {
      create(:roster, :market => @market, :contest_type => contest_type).fill_randomly.submit!
    }
    private_contest = create(:contest, :market => @market, :contest_type => contest_type, :user_cap => 2, :buy_in => 10)
    2.times {
      create(:roster, :market => @market, :contest_type => contest_type, :contest => private_contest).fill_randomly.submit!
    }
    private_contest_2 = create(:contest, :market => @market, :contest_type => contest_type, :user_cap => 2, :buy_in => 10)
    create(:roster, :market => @market, :contest_type => contest_type, :contest => private_contest_2).fill_randomly.submit!

    #verify the state of affairs
    assert_equal 6, @market.rosters.where("state = 'submitted'").length
    assert_equal 2, private_contest.rosters.length
    assert_equal 1, private_contest_2.rosters.length
    assert_equal 2, @market.contests.where("invitation_code is not null").length

    #close market, should move the one roster in the private contest to the public contest
    @market.open.close.reload

    #should be 3 contests: two public, one private
    assert_equal 'closed', @market.state
    assert_equal 3, @market.contests.length, "#{@market.contests.each {|c| c.inspect + '\n'}}"
    assert_equal 2, @market.contests.where("invitation_code is null").length
    assert_equal 0, @market.rosters.where("cancelled = true").length
    assert_equal 2, private_contest.reload.rosters.length
  end


  # create a market that has three games at three different times.
  # roster 1 buys some players. get the price of one of the players.
  # game 1 starts, update market
  # assert that the players available are only from the 2 remaining games
  # assert that the prices
  # roster 2 buys some players. repeat process
  # test "players pulled out of markets when game happens" do
  test "lock players" do
    setup_multi_day_market
    @market.publish.add_default_contests

    #find a $10 contest_type in the market's contest types
    contest_type = @market.contest_types.where(:buy_in => 10).first
    assert !contest_type.nil?, "contest type can't be nil"

    #buy some players randomly
    20.times {
      create(:roster, :market => @market, :contest_type => contest_type).fill_randomly
    }

    #open the market. ensure that shadow bets are removed
    @market = @market.open
    assert @market.shadow_bets == 0, "no shadow bets after open"
    assert @market.state == "opened"

    #print out the current prices
    roster = create(:roster, :market => @market, :contest_type => contest_type)
    prices1 = roster.purchasable_players

    #now make a game happen by setting the locked_at to the past for the first 18 players
    @market.market_players.first(18).each do |mp|
      mp.locked_at = Time.now - 1000
      mp.save!
    end
    @market = @market.lock_players

    #ensure that there are only 18 available players
    prices2 = roster.purchasable_players
    assert prices2.length == 18, "expected 18 for sale, found #{roster.purchasable_players.length}"

    #ensure that the prices for those 18 haven't changed
    p1 = Hash[prices1.map { |p| [p.id, p.buy_price] }]
    prices2.each do |p|
      # puts "player #{p.id}: #{p1[p.id]} -> #{p.buy_price}"
      assert (p1[p.id] - p.buy_price).abs < 1, "price equality? player #{p.id}: #{p1[p.id]} -> #{p.buy_price}"
    end

    #buy more players randomly
    20.times {
      create(:roster, :market => @market, :contest_type => contest_type).fill_randomly
    }

    prices3 = roster.purchasable_players
    #see how much the mean price has changed
    avg2 = prices2.collect(&:buy_price).reduce(:+)/18
    avg3 = prices3.collect(&:buy_price).reduce(:+)/18
    # puts "average price moved from #{avg2.round(2)} to #{avg3.round(2)}"
    # assert (avg2-avg3).abs < 1000
  end

  test "publish open and close" do
    setup_multi_day_market
    assert @market.players.length == 0
    @market = @market.publish
    @market.add_default_contests
    @market.reload
    assert @market.players.length == 36, "should be players"
    assert @market.contest_types.length > 0, "should be contest_types"
    assert @market.total_bets > 0
    assert @market.shadow_bets == @market.total_bets

    #open the market. should remove the shadow bets
    @market = @market.open
    # puts "market after open: #{@market.inspect}"
    assert @market.shadow_bets == 0, "shadow bets 0"
    assert @market.total_bets == 0, "bets 0"
    assert @market.state == "opened", "state is opened"
    #even if there are 0 bets, it shouldn't throw an error if we get player prices
    roster = create(:roster, :market => @market)
    assert roster.purchasable_players.length == 36

    #close market
    @market.close
    @market.reload
    assert_equal 'closed', @market.state, "should be closed, but is #{@market.state}"
  end

  test "publish detail" do
    setup_multi_day_market

    #set half the games tomorrow and half for the day after
    tomorrow, day_after = Time.now + 24*60*60, Time.now + 24*60*60*2
    @games[0].game_day, @games[0].game_time = tomorrow, tomorrow
    @games[1].game_day, @games[1].game_time = day_after, day_after
    @games.each {|g| g.save!; g.reload}

    #publish the market
    @market.publish
    assert @market.players.length == 36, "9*4=36"
    #make sure that half are locked tomorrow and half the day after
    locked_tomorrow = locked_day_after = 0
    @market.market_players.each do |p|
      if p.locked_at - tomorrow < 10
        locked_tomorrow += 1
      elsif p.locked_at - day_after < 10
        locked_day_after += 1
      else
        flunk("p.locked_at: #{p.locked_at}")
      end
    end
    assert locked_tomorrow == 18, "expected 18 locked tomorrow, but found #{locked_tomorrow}"
    assert locked_day_after == 18, "18 locked the day after, #{locked_day_after}"

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
