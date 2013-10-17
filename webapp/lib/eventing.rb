class Eventing
  CLYNG_EVENT_API = 'http://go.clyng.com/events/process'
  CLYNG_USER_API = 'http://go.clyng.com/api/user/setValues'
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

  # EVENT NAME MUST BE CAMEL CASED
  def self.report(user, event, data = {})
    return if Rails.env == 'test'
    params = default_params(user).merge({
      eventName: event,
    }).merge(data)
    Typhoeus.post(CLYNG_EVENT_API, headers: headers, body: params.to_json)
  end

=begin
curl -X PUT -H "Content-Type: application/json" –data '{
    "apiKey": "pk-18d8a70d-3f69-455f-ab2c-0dbd8c0d8685", // this is your Private key
    "userId" : "uid12345", 
    "email" : "john2@clyng.com", 
    "age" : 42
}' go.clyng.com/api/user/setValues
=end
  def self.update_user(user, data)
    return if Rails.env == 'test'
    params = default_params(user).merge(data)
    Typhoeus.post(CLYNG_USER_API, headers: headers, body: params.to_json)
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
      apiKey: CLYNG_SECRET
    }
  end

end
