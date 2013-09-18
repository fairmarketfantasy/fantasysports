require 'test_helper'

class RosterTest < ActiveSupport::TestCase

  setup do
    setup_simple_market
    @roster = create(:roster, :market => @market, :contest_type => @market.contest_types.first)
  end 

  #make sure that you can't play a h2h against yourself
  test "no self h2h" do
    h2h = @market.contest_types.where("max_entries = 2").first
    user1 = create(:user)
    user2 = create(:user)
    roster1 = Roster.generate(user1, h2h).submit!
    roster1.reload
    #should be in h2h contest
    contest1 = roster1.contest
    assert_equal roster1.contest_id, contest1.id
    refute_nil contest1.rosters.first, "#{contest1.rosters.explain}"

    #same user, same contest type
    roster2 = Roster.generate(user1, h2h).submit!
    #rosters should be in different contests
    refute_equal roster1.contest, roster2.contest

    roster3 = Roster.generate(user2, h2h).submit!
    roster4 = Roster.generate(user2, h2h).submit!
    roster5 = Roster.generate(user2, h2h).submit!

    #rosters 3 and 4 should have been allocated to the contests created by 1 and 2
    assert_equal 2, roster1.contest.rosters.size
    assert_equal 2, roster2.contest.rosters.size
    assert_equal 1, roster5.contest.rosters.size
  end


  test "submit puts roster in contest" do
    #find head to head
    h2h_type = @market.contest_types.where("max_entries = 2").first
    roster = create(:roster, :market => @market, :contest_type => h2h_type)
    roster.submit!
    contest = roster.contest
    
    assert_equal "submitted", roster.state
    assert_equal 1, contest.num_rosters

    #submit another roster to the same contest. should succeed as well.
    create(:roster, :market => @market, :contest_type => h2h_type).submit!
    assert_equal 2, contest.rosters.length

    #submitting a third should it to create a new one
    create(:roster, :market => @market, :contest_type => h2h_type).submit!
    assert_equal 2, contest.rosters.length
    assert_equal 2, @market.contests.length

    #private contests
    contest = create(:contest, :user_cap => 2, :market => @market, :contest_type => h2h_type, :invitation_code => "asdfasdfasdf")
    roster = create(:roster, :contest => contest, :market => @market, :contest_type => h2h_type)
    roster.submit!
    assert_equal contest, roster.contest
    assert_equal "submitted", roster.state

    #another joins the private contest
    create(:roster, :contest => contest, :market => @market, :contest_type => h2h_type).submit!
    assert_equal 2, contest.rosters.length

    #a third tries to join. should get booted
    begin
      create(:roster, :contest => contest, :market => @market, :contest_type => h2h_type).submit!
      flunk("should have failed. #{contest.rosters.length} rosters. #{roster.contest}")
    rescue
      #good
    end
  end

  test "fill randomly" do
    setup_multi_day_market
    @market.publish

    #find a $10 contest_type in the market's contest types
    contest_type = create(:contest_type, :market => @market)

    #create a roster and have it buy things
    roster = create(:roster, :market => @market, :contest_type => contest_type)
    assert roster.purchasable_players.length == 36, "36 players for sale (9x4)"
    roster.fill_randomly.submit!
    # roster.reload
    assert roster.players.length == 9, "roster should be filled, but only had #{roster.players.length}"
    assert roster.remaining_salary < 100000
    # puts "remaining salary: #{roster.remaining_salary}"
   end

  test "adding or removing players from roster affects salary" do
    @roster.submit!
    player = @roster.purchasable_players.first
    initial_cap = @roster.remaining_salary
    assert_difference('@roster.reload.remaining_salary.to_f', -player.buy_price) do
      @roster.add_player player
    end
    player = @roster.players.with_sell_prices(@roster).sellable.first
    assert_difference('@roster.reload.remaining_salary.to_f', player.sell_price) do
      @roster.remove_player player
    end
    assert_equal @roster.remaining_salary, initial_cap
  end 

  #purchasing a player causes the price to go up
  test "purchasing a player affects prices" do
    player = @roster.purchasable_players.first
    @other_roster = create(:roster, :market => @market)
    initial_price = player.buy_price
    @roster.add_player player

    #because the first roster has not been submitted, the price should not have changed
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert_equal initial_price, player.buy_price

    @roster.submit!
    assert_equal 'submitted', @roster.state
    assert_equal 1, @roster.players.length
    assert_equal 1000, @roster.buy_in
    @market.reload
    market_player = @market.market_players.where("player_id = #{player.id}").first

    #now the price of the player should be higher
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert player.buy_price > initial_price, "buy price: #{player.buy_price}, initial price: #{initial_price}"

    @roster.remove_player player
    
    #should be back to the original price
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert_equal player.buy_price, initial_price

    #purchasing with a submitted roster should shift prices
    @roster.add_player player
    #now the price of the player should be higher
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert player.buy_price > initial_price, "buy price: #{player.buy_price}, initial price: #{initial_price}"
  end

  test "creating and canceling roster affects account balance" do
    user = create(:user)
    user.customer_object = create(:customer_object, user: user)
    initial_balance = user.customer_object.balance
    roster = nil
    contest_type = @market.contest_types.where(:buy_in => 1000).first
    assert_difference("TransactionRecord.count", 1) do
      roster = Roster.generate(user, contest_type)
      roster.submit!
    end
    assert_equal  initial_balance - 1000, user.customer_object.reload.balance
    assert_difference("TransactionRecord.count", 1) do
      roster.destroy
    end
    assert_equal  initial_balance, user.customer_object.reload.balance

    #creating and canceling a roster before submitting it should not affect balance
    roster = Roster.generate(user, contest_type)
    assert_equal  initial_balance, user.customer_object.reload.balance
    roster.destroy
    assert_equal  initial_balance, user.customer_object.reload.balance
  end

  test "cancelling roster cleans up after itself" do
    @roster.submit!
    player = @roster.purchasable_players.first
    market = @roster.market
    market.reload
    total_bets = market.total_bets
    assert_difference ['RostersPlayer.count', 'MarketOrder.count'], 1 do
      @roster.add_player player
    end
    assert market.reload.total_bets > total_bets, "adding player increases total bets"
    assert_difference ['RostersPlayer.count', 'MarketOrder.count'], -1 do
      @roster.destroy
    end
    assert_equal market.reload.total_bets, total_bets, "destroying roster decreases total bets"
  end

end
