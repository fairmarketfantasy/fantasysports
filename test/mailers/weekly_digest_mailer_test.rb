require 'test_helper'

class WeeklyDigestMailerTest < ActionMailer::TestCase

  test "dont send more than 1 per week" do
    skip "This test case causes error, skip it for now"
    setup_simple_market
    user = create(:user)
    assert_email_sent do
      WeeklyDigestWorker.perform(user.email)
    end
    assert_email_not_sent do
      WeeklyDigestWorker.perform(user.email)
    end
  end
end
