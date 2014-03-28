Fantasysports::Application.configure do
  SITE = "https://staging.predictthat.com"
  SPORTS_DATA_API_KEY = "dmefnmpwjn7nk6uhbhgsnxd6"
  SPORTS_DATA_IMAGES_API_KEY = "yq9uk9qu774eygre2vg2jafe"
  FACEBOOK_APP_ID = "380919122046469"
  FACEBOOK_APP_SECRET = "3fd8aed4901ca0a22b642f32a580c841"
  AWS_ACCESS_KEY="AKIAJXV4UPD3IV4JK6DA"
  AWS_SECRET_KEY="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"
  S3_BUCKET = 'fairmarketfantasy-dev'

  STRIPE_SECRET = "sk_test_yYZU66ChxfF3LhCJvDYQTCNr"
  STRIPE_KEY = "pk_test_IJGbzv2tpcV1TAAwaEP8MDuJ"

  CLYNG_SECRET = "pk-18d8a70d-3f69-455f-ab2c-0dbd8c0d8685"
  CLYNG_PUBLISHABLE = "84bc73ca-5947-4357-b37b-aa5692289113"

  TSN_API_KEY = 'DgwWTPEQMoQNT-YxtxFB'

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both thread web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like nginx, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Disable Rails's static asset server (Apache or nginx will already do this).
  config.serve_static_assets = true

  # Compress JavaScripts and CSS.
  config.assets.js_compressor = :uglifier
  # config.assets.css_compressor = :sass

  # Do not fallback to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Generate digests for assets URLs.
  config.assets.digest = true

  # Version of your assets, change this if you want to expire all your assets.
  config.assets.version = '1.0'

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for nginx

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  #config.force_ssl = true

  # Set to :debug to see everything in the log.
  config.log_level = :info

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :subdomain, :uuid ]

  # Use a different logger for distributed setups.
  # config.logger = ActiveSupport::TaggedLogging.new(SyslogLogger.new)

  # Use a different cache store in production.
  #config.cache_store = :file_store, File.join(Rails.root, 'tmp', 'cache')
  elasticache = Dalli::ElastiCache.new('staging-001.0nuqd9.0001.usw2.cache.amazonaws.com:11211')
  config.cache_store = :dalli_store, elasticache.servers, {:expires_in => 1.day, :compress => true}


  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = "http://assets.example.com"

  # Precompile additional assets.
  # application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
  config.assets.precompile += %w( flat-ui.css fmf.css fonts.css terms.js terms.css )

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false
  config.action_mailer.default_url_options = { :host => 'staging.predictthat.com' }
  config.action_mailer.delivery_method = :sendmail

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Disable automatic flushing of the log to improve performance.
  # config.autoflush_log = false

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new
end
