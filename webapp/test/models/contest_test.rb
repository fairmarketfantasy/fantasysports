require 'test_helper'

class ContestTest < ActiveSupport::TestCase
  test "payday" do
    setup_simple_market
    contest_type = @market.contest_types.where("max_entries = 2 and buy_in = 100 and NOT takes_tokens").first
    refute_nil contest_type

    user1 = create(:user)
    user1.customer_object = create(:customer_object, user: user1)
    user2 = create(:user)
    user2.customer_object = create(:customer_object, user: user2)
    
    roster1 = Roster.generate(user1, contest_type).submit!
    roster2 = Roster.generate(user2, contest_type).submit!
    #make sure rosters are in same contest
    assert_equal roster1.contest, roster2.contest

    roster1.contest_rank = 1
    roster2.contest_rank = 2
    roster1.save!
    roster2.save!

    total_payout = contest_type.get_payout_structure.sum
    rake = total_payout * contest_type.rake
    assert_difference 'user1.customer_object.reload.balance.to_f', contest_type.buy_in * 2 - 2 * contest_type.buy_in * contest_type.rake do
      assert_difference 'user2.customer_object.reload.balance.to_f', 0 do
        roster1.contest.payday!
      end
    end
    assert_equal roster1.contest.rake_amount.to_f, TransactionRecord.where(:event => 'rake', :contest_id => roster1.contest_id).first.amount.to_f
    user1.reload
    user2.reload
    assert user1.customer_object.balance > user2.customer_object.balance

    roster1.reload
    roster2.reload
    assert roster1.amount_paid > 0
    assert_equal 0,  roster2.amount_paid
    assert roster1.paid_at && roster2.paid_at
    assert roster1.state == 'finished'
    assert roster2.state == 'finished'
  end

  #test auxillary functions
  test "payday auxillary functions" do
    contest_type = create(:contest_type, :payout_structure => [5,4,3,2,1].to_json, :rake => 0.25, :buy_in => 2, :max_entries => 10 # Make the validator happy
                         )
    ranks = [1,1,3,3,5,5,5,8,9,10]
    rank_payment = contest_type.rank_payment(ranks)
    expected = {1 => 9, 3 => 5, 5 => 1}
    assert_equal expected, rank_payment

    rosters = [create(:roster, :contest_rank => 1),
               create(:roster, :contest_rank => 2),
               create(:roster, :contest_rank => 2),
               create(:roster, :contest_rank => 4)]
    by_rank = Contest._rosters_by_rank(rosters)
    assert_equal by_rank.length, 3
    assert_equal by_rank[2].length, 2
  end

  def play_single_contest(ct, num_rosters = 10)
    users = (1..num_rosters).map{ create(:paid_user) }
    @rosters = []
    users.each_with_index do |user, i|
      roster = Roster.generate(user, ct)
      @rosters << roster
      roster.submit!
      next if i == 0
      @players[1..i].each{|player| roster.add_player(player) }
    end
    @market.update_attribute(:closed_at, Time.new - 1.minute)
    @players.each do |p| 
      StatEvent.create!(
        :game_stats_id => @game.stats_id,
        :player_stats_id => p.stats_id,
        :point_value => 1,
        :activity => 'rushing',
        :data => ''
      )
    end
    @rosters.each{|r| r.update_attribute(:remaining_salary, 100)} # Fake out the score compensator
    @market.update_attribute :state, 'opened'
    @game.update_attribute :status, 'closed'
    Market.tend # Close it
    Market.tend # Complete it
  end

  test 'record keeping' do
    setup_simple_market
    ct = @market.contest_types.where("name='194' AND buy_in = 1000 AND max_entries = 10").first
    play_single_contest(ct)
    @rosters.each_with_index do |r, i|
      r.reload
      if i <5
        assert_equal 1, r.losses
        assert_equal 0, r.wins
      else
        assert_equal 0, r.losses
        assert_equal 1, r.wins
      end
    end
  end

  test 'unfilled h2h rr record keeping' do
    setup_simple_market
    ct = @market.contest_types.where("name='h2h rr' AND buy_in = 900 AND max_entries = 10").first
    play_single_contest(ct, 3)
    @rosters.each_with_index do |r, i|
      r.reload
      assert_equal 2-i, r.losses
      assert_equal i, r.wins
      assert_equal 7 * 100 + i * 194, r.amount_paid.to_i
    end
  end

  test 'h2h rr record keeping' do
    setup_simple_market
    ct = @market.contest_types.where("name='h2h rr' AND buy_in = 900 AND max_entries = 10").first
    play_single_contest(ct)
    @rosters.each_with_index do |r, i|
      r.reload
      assert_equal 9-i, r.losses
      assert_equal i, r.wins
    end
  end

  test 'league join' do
    setup_simple_market
      # :start_day => (opts[:market].started_at - 6.hours).strftime("%w").to_i + 1,
    ct = @market.contest_types.first
    roster = Roster.generate(create(:paid_user), ct)
    league = create(:league)
    contest = create(:contest, market: @market, league_id: league.id, contest_type_id: ct.id)
    roster.contest = contest
    roster.save!
    roster.submit!
    assert roster.owner.leagues.include?(contest.league)
  end

  describe Contest do

    before(:all) do
      setup_simple_market
      @user = create(:paid_user)
      @contest = Contest.new(owner:     @user,
                             contest_type:  create(:contest_type),
                             buy_in:    10,
                             market_id: @market.id)
    end

  end
end
