require 'test_helper'

class RosterTest < ActiveSupport::TestCase

  setup do
    setup_new_market
    @market.publish
    @roster = create(:roster, :market => @market)
  end 

  test "fill randomly" do
    setup_multi_day_market
    @market.publish

    #find a $10 contest_type in the market's contest types
    contest_type = @market.contest_types.where(:buy_in => 10).first

    #create a roster and have it buy things
    roster = create(:roster, :market => @market, :contest_type => contest_type)
    assert roster.purchasable_players.length == 36, "36 players for sale (9x4)"
    roster.fill_randomly
    # roster.reload
    assert roster.players.length == 9, "roster should be filled, but only had #{roster.players.length}"
    assert roster.remaining_salary < 100000
    # puts "remaining salary: #{roster.remaining_salary}"
   end

  test "adding or removing players from roster affects salary" do
    player = @roster.purchasable_players.first
    initial_cap = @roster.remaining_salary
    assert_difference('@roster.reload.remaining_salary.to_f', -player.buy_price) do
      @roster.add_player player
    end
    player = @roster.sellable_players.first
    assert_difference('@roster.reload.remaining_salary.to_f', player.sell_price) do
      @roster.remove_player player
    end
    assert_equal @roster.remaining_salary, initial_cap
  end 

  test "market affects player prices" do
    player = @roster.purchasable_players.first
    @other_roster = create(:roster, :market => @market)
    initial_salary = player.buy_price
    @roster.add_player player
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert player.buy_price > initial_salary
    @roster.remove_player player
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert_equal player.buy_price, initial_salary
  end

  test "creating and canceling roster affects account balance" do
    user = create(:user)
    user.customer_object = create(:customer_object, user: user)
    initial_balance = user.customer_object.balance
    roster = nil
    assert_difference("TransactionRecord.count", 1) do
      roster = Roster.generate(user, @market.contest_types.where(:buy_in => 10).first)
    end
    assert_equal  initial_balance - 10, user.customer_object.reload.balance
    assert_difference("TransactionRecord.count", 1) do
      roster.destroy
    end
    assert_equal  initial_balance, user.customer_object.reload.balance
  end

  test "cancelling roster cleans up after itself" do
    player = @roster.purchasable_players.first
    market = @roster.market
    market.reload
    bets = market.total_bets
    assert bets == 1000
    assert_difference ['RostersPlayer.count', 'MarketOrder.count'], 1 do
      @roster.add_player player
    end
    assert_difference ['RostersPlayer.count', 'MarketOrder.count'], -1 do
      @roster.destroy
    end
    assert_equal market.reload.total_bets, bets, "destroying roster decreases total bets"
  end

end
