Fantasysports::Application.configure do
  SITE = "http://localhost:3000"
  SPORTS_DATA_API_KEY = "dmefnmpwjn7nk6uhbhgsnxd6"
  SPORTS_DATA_IMAGES_API_KEY = "yq9uk9qu774eygre2vg2jafe"
  FACEBOOK_APP_ID = "162183927304348"
  FACEBOOK_APP_SECRET = "657c1163073b2b31ea66e13670473a28"
  AWS_ACCESS_KEY="AKIAJXV4UPD3IV4JK6DA"
  AWS_SECRET_KEY="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"
  S3_BUCKET = 'fairmarketfantasy-dev'

  STRIPE_SECRET = "sk_test_yYZU66ChxfF3LhCJvDYQTCNr"
  STRIPE_KEY = "pk_test_IJGbzv2tpcV1TAAwaEP8MDuJ"

  CLYNG_SECRET = "pk-18d8a70d-3f69-455f-ab2c-0dbd8c0d8685"
  CLYNG_PUBLISHABLE = "84bc73ca-5947-4357-b37b-aa5692289113"

  TSN_API_KEY = 'DgwWTPEQMoQNT-YxtxFB'

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
