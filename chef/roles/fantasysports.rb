name 'fantasysports'
description 'single application server'

run_list(
  'recipe[apt]',
  'recipe[build-essential]',
  'recipe[openssl]',
  'recipe[git]',
  'recipe[aliases]',
  'recipe[application]',

  # worker
  'recipe[golang]',

  # db
  'recipe[postgresql]',
  'recipe[postgresql::libpq]',
  'recipe[postgresql::server]',
  'recipe[postgresql::client]',

  # web
  'recipe[nginx]',
  'recipe[fantasysports]'
)


