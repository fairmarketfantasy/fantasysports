CarrierWave.configure do |config|
  config.fog_credentials = {
    :provider              => 'AWS',
    :aws_access_key_id     => AWS_ACCESS_KEY,
    :aws_secret_access_key => AWS_SECRET_KEY,
    :region                => 'us-west-2'
  }
  config.fog_directory = 'fairmarketfantasy-dev'
  config.asset_host = 'https://s3.amazonaws.com'
  config.fog_public = false
  config.fog_attributes = {'Cache-Control'=>'max-age=315576000'}
  config.cache_dir = "#{Rails.root}/tmp/uploads"
  config.storage = :fog


  if Rails.env.test?
    config.storage = :file
    config.enable_processing = false
  end
end