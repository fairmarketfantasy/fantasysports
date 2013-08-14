require 'test_helper'

class GameEventTest < ActiveSupport::TestCase
  describe GameEvent do
    let(:ge_1) { game_events(:one) }

    describe "scopes" do
      describe ".after_seq_number" do
        let(:sn) { ge_1.sequence_number }
        it "should should not return a record with an equal sequence number" do
          GameEvent.after_seq_number(sn).wont_include(ge_1)
        end

        it "should return a record with a sequence number 1 higher" do
          GameEvent.after_seq_number(sn - 1).must_include(ge_1)
        end
      end
    end
  end
end
