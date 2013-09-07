require 'test_helper'

class UserTest < ActiveSupport::TestCase

  describe User do

    let(:user) { build(:user) }

    describe "#image_url" do

      it "should default to gravatar" do
        assert /gravatar/.match(user.image_url)
      end

    end
  end
end
