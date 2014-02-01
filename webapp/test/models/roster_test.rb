require 'test_helper'

class RosterTest < ActiveSupport::TestCase

  setup do
    setup_simple_market
    initialize_player_bets(@market)
    @roster = create(:roster, :market => @market, :contest_type => @market.contest_types.first)
  end 

  #make sure that you can't play a h2h against yourself
  test "no self h2h or other contests" do
    h2h = @market.contest_types.where("max_entries = 2 and not takes_tokens").first
    user1 = create(:paid_user)
    user2 = create(:paid_user)
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

    @market.contest_types.each do |contest_type|
      user = create(:paid_user)
      roster1 = Roster.generate(user, contest_type).submit!
      roster2 = Roster.generate(user, contest_type).submit!
      if contest_type.max_entries == 0
        assert_equal roster1.contest, roster2.contest
      else
        assert_not_equal roster1.contest, roster2.contest
      end
    end
  end

  test "submit adds bets to market" do
    assert @roster.buy_in > 0, "buy in > 0"
    @roster.fill_randomly
    assert @roster.players.size > 0, "has players"
    bets_before = @market.total_bets
    @roster.submit!
    assert_equal @roster.state, 'submitted', "roster is submitted"
    assert @market.total_bets = bets_before + @roster.players.size * @roster.buy_in, "increased total bets"
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
    contest = create(:contest, :user_cap => 2, :market => @market, :contest_type => h2h_type, :invitation_code => "asdfasdfasdf", :private => true)
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
    @market.update_attribute(:opened_at, Time.new-1.minute)
    @market.open
    player = @roster.purchasable_players.first
    initial_cap = @roster.remaining_salary
    assert_difference('@roster.reload.remaining_salary.to_f', -player.buy_price) do
      @roster.add_player player, player.positions.first.position
    end
    player = @roster.players.with_sell_prices(@roster).sellable.first
    assert_difference('@roster.reload.remaining_salary.to_f', player.sell_price) do
      @roster.remove_player player
    end
    assert_equal @roster.remaining_salary, initial_cap
  end 

  #purchasing a player causes the price to go up
  test "purchasing a player affects prices" do
    initialize_player_bets(@market)
    player = @roster.purchasable_players.first
    @other_roster = create(:roster, :market => @market, :contest_type => @market.contest_types.first)
    initial_price = player.buy_price
    @roster.add_player player, player.positions.first.position

    #because the first roster has not been submitted, the price should not have changed
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert_equal initial_price.to_i, player.buy_price.to_i

    @roster.submit!
    assert_equal 'submitted', @roster.state
    assert_equal 1, @roster.players.length
    assert_equal 1000, @roster.buy_in
    @market.reload
    market_player = @market.market_players.where("player_id = #{player.id}").first

    #now the price of the player should be higher
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert player.buy_price > initial_price, "buy price: #{player.buy_price.to_i}, initial price: #{initial_price.to_i}"

    @roster.remove_player player
    
    #should be back to the original price
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert_equal player.buy_price, initial_price

    #purchasing with a submitted roster should shift prices
    @roster.add_player player, player.positions.first.position
    #now the price of the player should be higher
    player = @other_roster.purchasable_players.where(:id => player.id).first
    assert player.buy_price > initial_price, "buy price: #{player.buy_price}, initial price: #{initial_price}"
  end

  test "creating and canceling roster affects account balance" do
    user = create(:paid_user)
    initial_entries  = user.customer_object.monthly_contest_entries
    roster = nil
    contest_type = @market.contest_types.where(:buy_in => 1000).first
    assert_difference("TransactionRecord.count", 1) do
      roster = Roster.generate(user, contest_type)
      roster.submit!
    end
    assert_equal initial_entries + 1, user.customer_object.reload.monthly_contest_entries
    assert_difference("TransactionRecord.count", 1) do
      roster.cancel!('test')
    end
    assert_equal  initial_entries, user.customer_object.reload.monthly_contest_entries

    #creating and canceling a roster before submitting it should not affect balance
    roster = Roster.generate(user, contest_type)
    assert_equal  initial_entries, user.customer_object.reload.monthly_contest_entries
    roster.destroy
    assert_equal  initial_entries, user.customer_object.reload.monthly_contest_entries
  end

  test "cancelling roster cleans up after itself" do
    @roster.submit!
    player = @roster.purchasable_players.first
    market = @roster.market
    market.reload
    total_bets = market.total_bets
    assert_difference ['RostersPlayer.count', 'MarketOrder.count'], 1 do
      @roster.add_player player, player.positions.first.position
    end
    assert market.reload.total_bets > total_bets, "adding player increases total bets"
    assert_difference ['RostersPlayer.count', 'MarketOrder.count'], -1 do
      @roster.destroy
    end
    assert_equal market.reload.total_bets, total_bets, "destroying roster decreases total bets"
  end

  test "adding a real user to a contest bumps generated rosters" do
    contest_type = @market.contest_types.where('max_entries = 12').first
    roster = create(:roster, :market => @market, :contest_type => contest_type)
    roster.submit!
    roster.contest.fill_with_rosters(1.0)
    contest = roster.contest
    contest.num_generated
    (1..11).each do |i|
      assert_equal 12-i, contest.reload.num_generated
      create(:roster, :market => @market, :contest_type => contest_type).submit!
      assert_equal 12, contest.reload.num_rosters
    end
    assert_equal 0, contest.reload.num_generated
    assert_equal 1, Contest.count
    create(:roster, :market => @market, :contest_type => contest_type).submit!
    assert_equal 2, Contest.count
  end

  test "cancelling roster pays out properly" do
    roster2 = create(:roster, :market => @market, :contest_type => @market.contest_types.where('NOT takes_tokens').first)
    roster2.submit!

    assert_difference 'TransactionRecord.count', 1 do
      assert_difference 'roster2.owner.customer_object.reload.monthly_contest_entries', -1 do
        roster2.cancel!('reason')
      end
    end
  end

  test "swapping benched players" do
    @market.update_attribute(:opened_at, Time.new - 1.minute)
    @market.open
    @roster.fill_pseudo_randomly5
    players = @roster.players.first(2)
    players.each{|p| p.update_attribute(:removed, true) }
    Market.tend
    # Neither benched player is still there
    assert_equal players.map(&:id), players.map(&:id) - @roster.players.reload.map(&:id)
  end

  test "entering lolla twice" do
    add_lollapalooza @market
    lolla = @market.contest_types.where(:name => '0.13k').first
    user1 = create(:paid_user)
    assert_difference 'user1.customer_object.reload.monthly_contest_entries', 2 do
      assert_difference 'user1.customer_object.reload.monthly_contest_entries', 1 do
        Roster.generate(user1, lolla).submit!
      end
      Roster.generate(user1, lolla).submit!
    end
  end

  test "re-scoring a roster" do
    @market.update_attribute(:opened_at, Time.new - 1.minute)
    @market.open
    contest_type = @market.contest_types.where(:name => 'h2h', :buy_in => 1000, :takes_tokens => false).first
    roster1 = create(:roster, :market => @market, :contest_type => contest_type)
    roster2 = create(:roster, :market => @market, :contest_type => contest_type)
    user1 = roster1.owner
    user2 = roster2.owner
    contest = nil
    pre_count = nil
    assert_difference 'user1.customer_object.reload.monthly_contest_entries', 1 do
      assert_difference 'user1.customer_object.reload.monthly_winnings', 1900 do
        roster1.fill_randomly.submit!
        begin
          roster2.fill_randomly.submit!
        end while roster1.players.map(&:id) == roster2.players.map(&:id) # just make sure the rosters aren't identical

        roster1.players.limit(5).each do |p|
          StatEvent.create!(
            :game_stats_id => @game.stats_id,
            :player_stats_id => p.stats_id,
            :point_value => 1,
            :activity => 'rushing',
            :data => ''
          )
        end
        @market.closed_at = Time.new
        @game.update_attributes(:home_team_status => '{"points": 14}', :away_team_status => '{"points": 7}', :status => 'closed')
        @market.save!
        contest = roster1.contest
        assert_equal contest, roster2.contest
        Market.tend
        pre_count = roster1.contest.transaction_records.count
      end

      StatEvent.delete_all

      roster2.players.limit(5).each do |p|
        StatEvent.create!(
          :game_stats_id => @game.stats_id,
          :player_stats_id => p.stats_id,
          :point_value => 1,
          :activity => 'rushing',
          :data => ''
        )
      end
      contest.revert_payday!
      assert_equal 2*pre_count-2, contest.transaction_records.reload.count
    end

    assert_difference 'user1.customer_object.reload.monthly_winnings', 0 do
      assert_difference 'user2.customer_object.reload.monthly_winnings', 1900 do
        contest.payday!
      end
    end
  end

  test "adding same bonus twice" do
    @roster.submit!
    @roster.add_bonus('twitter_share')
    @roster.add_bonus('twitter_share')
    assert_equal Roster::ROSTER_BONUSES['twitter_share'], @roster.bonus_points
    @market.update_attribute(:opened_at, Time.new - 1.minute)
    Market.tend
    assert_equal @roster.bonus_points, @roster.reload.score
  end

end
