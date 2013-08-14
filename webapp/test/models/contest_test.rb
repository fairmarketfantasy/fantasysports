require 'test_helper'

class ContestTest < ActiveSupport::TestCase
  describe Contest do

    describe "after create" do
      it "should create a roster for the owner" do
        u = users(:one)
        m = markets(:one)
        assert_difference("User.find(#{u.id}).contests.count", 1) do
          assert_difference("User.find(#{u.id}).contest_rosters.count", 1) do
            c = Contest.new(owner: u, type: "194", buy_in: 10, market_id: m.id)
            c.save!
          end
        end
      end
    end
  end
end
