PayPal::SDK.load("config/paypal.yml", Rails.env)
PayPal::SDK.logger = Rails.logger
PAYPAL_OWNER = Rails.env == 'production' ? 'bpilch@hotmail.com' : 'bpilch-facilitator@hotmail.com'
