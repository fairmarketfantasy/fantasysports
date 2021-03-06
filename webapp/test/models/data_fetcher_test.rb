require 'test_helper'

class DataFetcherTest < ActiveSupport::TestCase
  test "get_pt_value" do
    assert_equal 31, DataFetcher.get_pt_value(+113, -123)
    assert_equal 26, DataFetcher.get_pt_value(-123, +113)
  end
end
