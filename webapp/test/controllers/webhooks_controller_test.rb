require 'test_helper'

class WebhooksControllerTest < ActionController::TestCase

  setup do
    sign_in(users(:one))
  end

  def wh_dispute_stub
    {
      id: "evt_DJFeM6xRbjB7pl",
      livemode: true,
      object: "event",
      type: "charge.dispute.created",
      charge: "xxx",
      created: 1376987673,
      status: "needs_response",
      livemode: false,
      currency: "usd",
      object: "dispute",
      reason: "general",
      balance_transaction: "txn_2OcBDwTgO2Z05Q",
      evidence_due_by: 1378684799,
      evidence: 'null'
    }
  end

  test "post dispute" do
    @request.env["RAW_POST_DATA"] = wh_dispute_stub.to_json
    co = customer_objects(:one)
    CustomerObject.stubs(:find_by_charge_id).returns(co)
    post :new
    assert co.locked, "Customer object should be locked"
    assert_response :success
  end
end
