require 'test_helper'

class PredictionSerializerTest < ActiveSupport::TestCase
  let(:prediction) { create(:prediction) }

  def test_that_kitty_can_eat
    assert_equal "OHAI!", @meme.i_can_has_cheezburger?
  end
end
