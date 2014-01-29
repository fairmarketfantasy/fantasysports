require 'test_helper'

class PlayerTest < ActiveSupport::TestCase

  describe Player do

    describe ".autocomplete" do

      let(:mcfadden) { p = create(:player, name: "Darren McFadden"); PlayerPosition.create!(:player_id => p.id, :position => "RB"); p }

      it "should take a string and return the right results" do
        Player.autocomplete("Darr").must_include(mcfadden)
      end

      it "should return results for last name" do
        Player.autocomplete("McF").must_include(mcfadden)
      end

      it "should return results for a lowercase name" do
        Player.autocomplete("darr").must_include(mcfadden)
      end

      it "should not return results when there is no match" do
        Player.autocomplete("Noone is here").must_be_empty
      end

    end

    describe "scopes" do

      before(:all) do
        setup_simple_market
      end

      let(:player1) { @team1.players.first }
      let(:player2) { @team2.players.first }

      describe ".on_team" do
        let(:result)  { Player.on_team(@team1) }

        it "should return players on a team" do
          result.must_include(player1)
          result.wont_include(player2)
        end
      end

    #   # # describe ".in_contest" do
    #   # # end

      describe ".in_game" do
        let(:result)  { Player.in_game(@game) }

        it "should return players in a game" do
          result.must_include(player1)
          result.must_include(player2)
        end
      end

    end

    describe "tracking benched games" do
      it "should work" do
        setup_multi_day_market
        Market.open # open it
        game1 = @games.first
        # Pick a few players and add stat events
        players = game1.players.sort_by{|p| p.id }.slice(0, 6)
        players.each do |player|
          StatEvent.create!(
            :game_stats_id => game1.stats_id,
            :player_stats_id => player.stats_id,
            :point_value => 1,
            :activity => 'rushing',
            :data => '')
        end
        game1.update_attribute(:bench_counted_at, Time.now - 1.minute)
        Market.tend # mark some players as benched
        # Assert that benched games are allocated properly
        game1.players.each do |p|
          if players.include?(p)
            assert_equal 0, p.benched_games
          else
            assert_equal 1, p.benched_games
          end
        end

        setup_multi_day_market2
        Market.tend # open it

        game1 = @games.first
        # Pick a few players and add stat events
        players2 = game1.players.sort_by{|p| p.id }.slice(0, 6)
        players2.each do |player|
          next if player.id % 2 == 0
          StatEvent.create!(
            :game_stats_id => game1.stats_id,
            :player_stats_id => player.stats_id,
            :point_value => 1,
            :activity => 'rushing',
            :data => '')
        end
        game1.update_attribute(:bench_counted_at, Time.now)
        Market.tend # mark some players as benched

        game1.players.each do |p|
          if players2.include?(p)
            assert_equal p.id % 2 == 0 ? 1 : 0, p.benched_games
          else
            assert_equal 2, p.benched_games
          end
        end
      end
    end
  end
end
