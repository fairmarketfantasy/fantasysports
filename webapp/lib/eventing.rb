class Eventing
  CLYNG_API = 'go.clyng.com/events/process'
=begin
curl -X PUT -H "Content-Type: application/json" –data '{
    "apiKey": "pk-18d8a70d-3f69-455f-ab2c-0dbd8c0d8685", // this is your Private key
    "userId":"uid12345",          // your id for the user, or you can use their email
    "eventName": "Upgrade Plan",  // the name of the event
    "Plan name" : "Great plan",   // parameters can be strings...
    "Monthly amount" : 30,        // ... or numbers...
    "Renewal date": "2013.12.01", // ... or dates...
    "Accepted terms" : "true",    // ... or boolean values...
    "fbAccessToken": "123456789"  // ... or even Facebook user access tokens...
}' go.clyng.com/events/process
=end
  def self.report(user, event, data)
    params = default_params.merge({
      eventName: event,
    }).merge(data)
    Typhoeus.post(CLYNG_API, headers: headers, body: params.to_json)
  end

  def self.update_user(user)

  end

  private

  def self.headers
    {
      'Accepts' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def self.default_params(user)
    {
      userId: user && user.email,
      environment: Rails.env,
      apiKey: "pk-18d8a70d-3f69-455f-ab2c-0dbd8c0d8685", # pk
    }

  end

end
