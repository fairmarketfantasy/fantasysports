yaml = Yaml.load_file(File.join(Rails.root, 'config', 'database.yml'))[Rails.env]
env = {
  PGHOST: yaml['host'],
  PGDATABASE: yaml['database'],
  PGPASSWORD: yaml['password'],
  PGUSER: yaml['username'],
}

system(env, "psql < #{File.join(Rails.root, '..', 'market', 'market.sql') } )
