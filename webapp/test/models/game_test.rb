require 'test_helper'

class GameTest < ActiveSupport::TestCase
  describe Game do
    describe "minimum data to save a record" do
      let(:g)  { Game.new( home_team: "a",
                          away_team: "b",
                          stats_id:   2,
                          game_day:  Date.today,
                          game_time: Time.now,
                          status:    "on schedule")
                }

      it "should be valid" do
        assert g.valid?
        assert g.save!
      end
    end
  end
end
