require File.expand_path('../boot', __FILE__)

require 'rails/all'
require 'devise_oauth2_providable'

# Setup api formats.
ActiveSupport.on_load(:active_model_serializers) do
  # Disable for all serializers (except ArraySerializer)
  ActiveModel::Serializer.root = false

  # Enable for ArraySerializer
  ActiveModel::ArraySerializer.root = "data"
end

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(:default, Rails.env)

module Fantasysports
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    Dir["#{Rails.root}/lib/ext/*"].each do |file|
      require file
    end
    config.autoload_paths += %W(#{Rails.root}/lib)
    config.autoload_paths += Dir["#{Rails.root}/lib/**/"]

    config.assets.enabled = true

    config.app_generators.stylesheet_engine :less

    # Counter rails bullshit
    config.generators do |g|
      g.orm             :active_record
      g.template_engine :erb
      g.test_framework  :test_unit, :fixture => false
      #g.stylesheets     false
      g.javascripts     false
      g.helper          false
    end

    config.devise_oauth2_providable.access_token_expires_in         = 1.day # 15.minute default
    config.devise_oauth2_providable.refresh_token_expires_in        = 6.months # 1.month default
    config.devise_oauth2_providable.authorization_token_expires_in  = 5.minute # 1.minute default

  end
end

require 'jsonh'
