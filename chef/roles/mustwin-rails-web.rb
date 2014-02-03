name 'mustwin-rails-web'
description 'A puma web server behind an AWS ELB'

override_attributes({'mustwin' => {'roles' => {'WEB' => true}}}) # Used by mustwin-basics

run_list(
  'recipe[apt]',
  'recipe[build-essential]',
  'recipe[git]',
  'recipe[aliases]',
  'recipe[awscli]',
  'recipe[postgresql]',
  'recipe[postgresql::libpq]',
  'recipe[postgresql::client]',
  'recipe[sendmail]',
  'recipe[openssl]',
  'recipe[mustwin-basics]',
)

