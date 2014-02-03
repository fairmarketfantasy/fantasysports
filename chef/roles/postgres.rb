name 'postgres'
description 'A single postgres server'
run_list(
  # db
  'recipe[postgresql]',
  'recipe[postgresql::libpq]',
  'recipe[postgresql::server]',
  'recipe[postgresql::client]',

  'recipe[mustwin-basics]',
  'recipe[mustwin-db-master]',
)
