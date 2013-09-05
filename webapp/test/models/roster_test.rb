require 'test_helper'

class RosterTest < ActiveSupport::TestCase

  setup do
    setup_simple_market
    @roster = create(:roster, :market => @market)
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

  test "submitting roster decreases account balance" do
    owner = @roster.owner
    owner.customer_object = create(:customer_object, user: owner)
    initial_balance = owner.customer_object.balance
    @players.each{|p| @roster.add_player(p) }

    assert_difference("TransactionRecord.count", 1) do
      @roster.submit!
    end
    assert_equal  initial_balance - @roster.buy_in, owner.customer_object.reload.balance
  end

end
