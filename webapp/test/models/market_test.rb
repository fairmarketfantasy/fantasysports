require 'test_helper'

class MarketTest < ActiveSupport::TestCase
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
            Market.opened_after(Time.now).closed_after(Time.now).page(1).order_closed_asc.inspect
          end
        end
      end
    end

  end
end
