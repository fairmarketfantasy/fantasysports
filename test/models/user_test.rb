require 'test_helper'

class UserTest < ActiveSupport::TestCase

  describe User do

    let(:user) { build(:user) }

    describe "avatar uploader" do

      let(:file) { fixture_file_upload('mickey.png', 'image/png') }

      it "should be able to take an upload" do
        user.avatar = file
        user.save!
        user.avatar.url.wont_be_nil
      end
    end
  end
end
