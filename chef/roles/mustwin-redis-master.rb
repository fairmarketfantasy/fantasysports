name 'mustwin-redis-master'
description 'A single redis master'
run_list(
  # db
  'recipe[redis]',
  'recipe[redis::server]',
)

