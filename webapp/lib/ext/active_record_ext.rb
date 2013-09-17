class ActiveRecord::Base
  def self.load_sql_file(file)
    yaml = YAML.load_file(File.join(Rails.root, 'config', 'database.yml'))[Rails.env]
    env = {
      'PGHOST'     => yaml['host'],
      'PGDATABASE' => yaml['database'],
      'PGPASSWORD' => yaml['password'],
      'PGUSER'     => yaml['username'],
    }
    system(env, "psql < #{file }" )
  end
end
