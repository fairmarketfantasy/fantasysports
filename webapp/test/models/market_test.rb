require 'test_helper'

class MarketTest < ActiveSupport::TestCase

  #Market.tend affects all markets at all stages.
  test "tend calls all things on all markets" do
    setup_multi_day_market
    Market.tend
    assert_equal 'published', @market.reload.state
    
    #zero shadow bets should cause it to open
    @market.shadow_bets = 0
    @market.save!
    Market.tend
    assert_equal 'opened', @market.reload.state

    #setting closed to before now should cause it to close
    @market.closed_at = Time.now - 60
    @market.save!
    Market.tend
    assert_equal 'closed', @market.reload.state
    @games.each do |game|
      game.status = 'closed'
      game.save!
    end
    Market.tend
    assert_equal 'complete', @market.reload.state
  end

  test "accepting rosters" do
    setup_simple_market
    assert @market.accepting_rosters?
    @market.state = 'opened'
    assert @market.accepting_rosters?
    @market.state = 'closed'
    refute @market.accepting_rosters?
  end

  #publish: 
  test "can only be published if state is empty or null" do
    setup_multi_day_market
    @market.publish
    begin
      @market.publish
      flunk "already published"
    rescue
    end
  end

  test "publish also updates player's stats" do

  end
  #updates player stats
  #sets shadow bets to 100k, should equal total bets, initial_shadow_bets
  #only starts if there is at least one game
  #removes all market players, market orders, and rosters
  #creates market players. weights shadow bets by ppg
  #sets state to published, price multiplier = 1, opened_at to earliest game,
  #closed_at to latest game start times

  test "publish sets opened and closed times" do
    setup_multi_day_market
    @market.publish
    assert @market.opened_at - @games[0].game_time < 10
    assert @market.closed_at - @games[1].game_time < 10
  end

  test "close on publish if all games started" do
    setup_multi_day_market
    @games.each do |game|
      game.game_day = game.game_time = Time.now.yesterday
      game.save!
    end

    @market.publish
    #because both games are over, should be closed
    assert_equal 'closed', @market.state
  end

  test "players are locked when their game starts" do
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


  test "close" do
    setup_simple_market
    #put 3 rosters public h2h and 3 in a private h2h
    contest_type = @market.contest_types.where("buy_in = 1000 and max_entries = 2").first
    refute_nil contest_type
    3.times {
      create(:roster, :market => @market, :contest_type => contest_type).fill_randomly.submit!
    }
    private_contest = create(:contest, :market => @market, :contest_type => contest_type, :user_cap => 2, :buy_in => 1000)
    2.times {
      create(:roster, :market => @market, :contest_type => contest_type, :contest => private_contest).fill_randomly.submit!
    }
    private_contest_2 = create(:contest, :market => @market, :contest_type => contest_type, :user_cap => 2, :buy_in => 1000)
    create(:roster, :market => @market, :contest_type => contest_type, :contest => private_contest_2).fill_randomly.submit!

    #verify the state of affairs
    assert_equal 6, @market.rosters.where("state = 'submitted'").length
    assert_equal 2, private_contest.rosters.length
    assert_equal 1, private_contest_2.rosters.length
    assert_equal 2, @market.contests.where("invitation_code is not null").length

    #close market, should move the one roster in the private contest to the public contest
    @market.shadow_bets, @market.initial_shadow_bets = 0, 0
    @market.save!
    @market.open
    assert_equal 'opened', @market.state
    @market.close

    #should be 3 contests: two public, one private
    assert_equal 'closed', @market.state
    assert_equal 3, @market.contests.length, "#{@market.contests.each {|c| c.inspect + '\n'}}"
    assert_equal 2, @market.contests.where("invitation_code is null").length
    assert_equal 0, @market.rosters.where("cancelled = true").length
    assert_equal 2, private_contest.reload.rosters.length
  end


  # lock_players removes players from the pool without affecting prices
  # it does so by updating the price multiplier
  test "lock players" do

    #setup a market and open it
    setup_multi_day_market
    @market.publish
    @market.opened_at = Time.now - 60
    @market.save!
    @market.open

    #buy some players randomly. plenty of bets
    contest_type = @market.contest_types.first
    10.times do
      create(:roster, :market => @market, :contest_type => contest_type).fill_randomly.submit!
    end

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
      create(:roster, :market => @market, :contest_type => contest_type).fill_randomly.submit!
    }

    prices3 = roster.purchasable_players
    #see how much the mean price has changed
    avg2 = prices2.collect(&:buy_price).reduce(:+)/18
    avg3 = prices3.collect(&:buy_price).reduce(:+)/18
    puts "average price moved from #{avg2.round(2)} to #{avg3.round(2)}"
    assert (avg2-avg3).abs < 1000
  end

  test "lock_players_all" do
    setup_multi_day_market
    over_game = @market.games.first
    future_game = @market.games.last
    over_game.game_day = Time.now.yesterday.beginning_of_day
    over_game.game_time = Time.now.yesterday
    over_game.save!
    Market.tend
    over_game.teams.each do |team|
      assert MarketPlayer.where(:player_stats_id => team.players.map(&:stats_id)).all?{|mp| mp.locked? }
    end
    future_game.teams.each do |team|
      assert MarketPlayer.where(:player_stats_id => team.players.map(&:stats_id)).all?{|mp| !mp.locked? }
    end
  end

  test "game play" do
    # Make a published market
    setup_simple_market
    ct1 = @market.contest_types.where("buy_in = 1000 and max_entries = 2").first
    ct2 = @market.contest_types.where("buy_in = 1000 and max_entries = 10").first
    ct3 = @market.contest_types.where("buy_in = 1000 and max_entries = 0").first
    # Fill 3 contest types with 11 users each.  H2H will create 6 contests. ct2 will have 2 contests, ct3 -> 100k
    users = (1..11).map{ create(:paid_user) }
    @rosters = {
      ct1 => [],
      ct2 => [],
      ct3 => []
    }
    users.each_with_index do |user, i|
      [ct1, ct2, ct3].each do |ct|
        roster = Roster.generate(user, ct)
        @players[0..i].each{|player| roster.add_player(player) }
        roster.submit!
        @rosters[roster.contest_type] << roster
      end
    end
    assert_equal 9, Contest.count
    # Open the market
    @market.opened_at = Time.now - 2.minutes
    @market.save!
    Market.tend
    assert_equal 'opened', @market.reload.state
    player = create(:player, :team => @team1)
    new_market_player = MarketPlayer.create!(:market_id => @market.id, :player_id => player.id, :locked_at => Time.new - 2.minutes)
    market_player = MarketPlayer.where(:player_id => @players[0].id, :market_id => @market.id).first
    market_player.update_attribute(:locked_at, Time.new - 2.minutes)
    Market.tend
    assert new_market_player.reload.locked
    assert market_player.reload.locked


    @rosters.each do |ct, rosters|
      # Available players shouldn't include locked players
      rosters.each do |roster|
        assert !Player.purchasable_for_roster(roster).include?(player)
      end
    end

    # Close the market
    @market.update_attribute(:closed_at, Time.new - 1.minute)
    @market.market_players.each{|mp| mp.update_attribute(:locked_at, Time.new - 1.minute) }
    Market.tend
    assert_equal 7, Contest.count
    assert_equal 'closed', @market.reload.state
    assert_equal 2, Roster.where(:state => 'cancelled').count
    assert_equal 2, Roster.where(:cancelled => true).count
    assert Player.purchasable_for_roster(@rosters[ct1][0]).empty? # spot check

    # Add some scores
    @players.each do |p| 
      StatEvent.create!(
        :game_stats_id => @game.stats_id,
        :player_stats_id => p.stats_id,
        :point_value => 1,
        :activity => 'rushing',
        :data => ''
      )
    end
    Market.tend
    # Rosters are scored and ranked
    @rosters.each do |ct, rosters|
      score = 0
      rank = 12 # just a number higher than the lowest rank
      rosters.each do |roster|
        roster.reload
        next if roster.cancelled?
        assert roster.score > score
        assert roster.contest_rank < rank if roster.contest_type != ct1
        score = roster.score
        rank = roster.contest_rank
      end
    end
    @game.update_attribute :status, 'closed'
    Market.tend

    # contests are paid out
    assert_equal "complete", @market.reload.state
    @rosters.each do |ct, rosters|
      rosters.each do |roster|
        roster.reload
        if roster.cancelled?
          assert_equal nil, roster.amount_paid
        else
          assert_equal ct.payout_for_rank(roster.contest_rank) || 0, roster.amount_paid.to_f
        end
      end
    end

    assert_equal 31, Roster.finished.count
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
