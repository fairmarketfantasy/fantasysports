require 'test_helper'

class PlayerTest < ActiveSupport::TestCase
  describe Player do
    let(:mj) { Player.find_by(name: "Michael Jordan") }

    describe "scopes" do
      describe ".autocomplete" do
        it "should take a string and return the right results" do
          Player.autocomplete("Mich").must_include(mj)
        end

        it "should return results for last name" do
          Player.autocomplete("Jordan").must_include(mj)
        end

        it "should return results for a lowercase name" do
          Player.autocomplete("mich").must_include(mj)
        end

        it "should not return results when there is no match" do
          Player.autocomplete("Noone is here").must_be_empty
        end
      end

      describe ".on_team" do
        let(:team_id) { teams(:one).id }
        it "should return players on a team" do
          Player.on_team(team_id).must_include(mj)
        end

        it "should not return players on a nonexistent team" do
          Player.on_team(10000).must_be_empty
        end
      end

      # describe ".in_contest" do
      # end

      describe ".in_game" do
        let(:game) { games(:one) }
        it "should return players in a game" do
          Player.in_game(game).must_include(mj)
        end
      end
    end
  end
end
