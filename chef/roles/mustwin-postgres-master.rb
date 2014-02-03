name 'mustwin-postgres-master'
description 'A single postgres master'
run_list(
  # db
  'recipe[postgresql]',
  'recipe[postgresql::libpq]',
  'recipe[postgresql::server]',
  'recipe[postgresql::client]',

  #'recipe[mustwin-basics]',
  'recipe[mustwin-postgres-master]',
)
