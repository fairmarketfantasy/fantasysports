require 'test_helper'

class RosterTest < ActiveSupport::TestCase

  setup do
    setup_simple_market
    @roster = create(:roster, :market => @market)
  end 

  test "adding or removing players from roster affects salary" do
    player = @players[0]
    initial_cap = @roster.remaining_salary
    assert_difference(@roster.remaining_salary, -player.salary) do
      @roster.add_player player
    end
    player.reload
    assert_difference(@roster.remaining_salary, player.salary) do
      @roster.remove_player player
    end
    assert_equal @roster.remaining_salary, initial_cap
  end 

  test "market affects player prices" do
    @other_roster = create(:roster, :market => @market)
    player = @players[0]
    initial_salary = player.salary
    @roster.add_player player
    assert player.reload.salary > initial_salary
    @roster.remove_player player
    assert_equal player.reload.salary, initial_salary
  end

  test "submitting an incomplete roster fails" do
    assert_raise HttpException do
      @roster.submit!
    end
  end

  test "submitting roster decreases account balance" do
    owner = @roster.owner
    initial_balance = owner.customer_object.balance
    @players.each{|p| @roster.add_player(p) }

    assert_difference("TransactionRecord.count", 1) do
      @roster.submit!
    end
    assert_equal  initial_balance - @roster.buy_in, owner.customer_object.reload.balance
  end

end
