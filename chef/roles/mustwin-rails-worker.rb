name 'mustwin-rails-worker'
description 'A puma worker'

override_attributes({'mustwin' => {'roles' => {'WORKER' => true}}}) # Used by mustwin-basics

# TODO: this is basically copied from mustwin-rails-web, just make a rails role and add worker stuff to another role
run_list(
  #'recipe[awscli]',
  'recipe[apt]',
  'recipe[build-essential]',
  'recipe[sendmail]',
  'recipe[git]',
  'recipe[aliases]',
  'recipe[postgresql]',
  'recipe[postgresql::libpq]',
  'recipe[postgresql::client]',
  'recipe[openssl]',
  'recipe[golang]', # Worker specific
  'recipe[mustwin-basics]',
)


