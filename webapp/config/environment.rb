# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Initialize the Rails application.
Fantasysports::Application.initialize!
TSN_API_KEY = ''

SPORT_ODDS_API_HOST = 'http://0.0.0.0'

WORLD_CUP_API_URL = SPORT_ODDS_API_HOST + '/SportsOddsAPI/Odds/5Dimes/SOC/'
PREDICTION_CHARGE = 15.to_d
