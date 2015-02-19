Fantasysports::Application.configure do
  SITE = "http://localhost:3000"
  SPORTS_DATA_API_KEY = ''
  SPORTS_DATA_IMAGES_API_KEY = ''
  FACEBOOK_APP_ID = ''
  FACEBOOK_APP_SECRET = ''
  AWS_ACCESS_KEY=''
  AWS_SECRET_KEY=''
  S3_BUCKET = ''

  STRIPE_SECRET = ''
  STRIPE_KEY = ''

  CLYNG_SECRET = ''
  CLYNG_PUBLISHABLE = ''

  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  #devise told me to:
  config.action_mailer.default_url_options = { :host => 'localhost:3000' }
  config.action_mailer.delivery_method = :file
  config.action_mailer.file_settings = {
    location: Rails.root.join('log/mail')
  }

  config.cache_store = :file_store, File.join(Rails.root, 'tmp', 'cache')

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations
  config.active_record.migration_error = :page_load

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true
  config.assets.digest = true
end
