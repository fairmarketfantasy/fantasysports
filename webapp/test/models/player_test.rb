require 'test_helper'

class PlayerTest < ActiveSupport::TestCase

  describe Player do

    describe ".autocomplete" do

      let(:mcfadden) { create(:player, name: "Darren McFadden", position: 'RB') }

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
  end
end
