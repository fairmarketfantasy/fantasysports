# This is a Rails Application

Learn it. Love it.  http://guides.rubyonrails.org


# Start the Server

`rails s`

# Rake Tasks

`rake -T`

Noteworthy:

Start the datafetcher fetching: `rake seed:data`
Start the market state machine: `rake market:tend`

# The Oauth API (used by iOS)

To get an OAuth token:

    $ curl -d 'client_id=fairmarketfantasy&client_secret=f4n7Astic&grant_type=password&username=fantasysports@mustw.in&password=F4n7a5y' 'http://vagrant.vm:3000/oauth2/token'
    {"access_token":"ACCESS_TOKEN_HERE","token_type":"bearer","expires_in":86399,"refresh_token":"REFRESH_TOKEN_HERE"}

To use an OAuth token to authenticate:

    $ curl -H 'Authorization: Bearer ACCESS_TOKEN_HERE' 'http://vagrant.vm:3000/users'


