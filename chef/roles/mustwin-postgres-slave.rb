name 'mustwin-postgres-slave'
description 'A single postgres slave'
run_list(
  # db
  'recipe[postgresql]',
  'recipe[postgresql::libpq]',
  'recipe[postgresql::server]',
  'recipe[postgresql::client]',

  #'recipe[mustwin-basics]',
  'recipe[mustwin-postgres-slave]',
)
