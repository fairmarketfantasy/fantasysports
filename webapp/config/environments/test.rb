Fantasysports::Application.configure do
  SITE = "localhost:3000"
  SPORTS_DATA_API_KEY = "un32n24mu43xpmk594dzvm2p"
  FACEBOOK_APP_ID = "162183927304348"
  FACEBOOK_APP_SECRET = "657c1163073b2b31ea66e13670473a28"
  STRIPE_PUBLISHABLE  = "pk_a3gdaHTfXJ2KTlM4GhBGwK8HmWQvB"
  STRIPE_SECRECT      = "5B95wcyZt8TpaQqUmBNqeObQQMa7oweD"
  # Settings specified here will take precedence over those in config/application.rb.

  # The test environment is used exclusively to run your application's
  # test suite. You never need to work with it otherwise. Remember that
  # your test database is "scratch space" for the test suite and is wiped
  # and recreated between test runs. Don't rely on the data there!
  config.cache_classes = true

  # Do not eager load code on boot. This avoids loading your whole application
  # just for the purpose of running a single test. If you are using a tool that
  # preloads Rails for running tests, you may have to set it to true.
  config.eager_load = false

  # Configure static asset server for tests with Cache-Control for performance.
  config.serve_static_assets  = true
  config.static_cache_control = "public, max-age=3600"

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = false

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  #devise told me to: 
  config.action_mailer.default_url_options = { :host => 'localhost:3000' }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr
end
