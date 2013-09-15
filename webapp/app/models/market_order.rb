class MarketOrder < ActiveRecord::Base
  belongs_to :roster

  # THIS IS A UTILITY FUNCTION, DO NOT CALL IT FROM THE APPLICATION
  def self.load_sql_functions
    yaml = YAML.load_file(File.join(Rails.root, 'config', 'database.yml'))[Rails.env]
    env = {
      'PGHOST'     => yaml['host'],
      'PGDATABASE' => yaml['database'],
      'PGPASSWORD' => yaml['password'],
      'PGUSER'     => yaml['username'],
    }
    system(env, "psql < #{File.join(Rails.root, '..', 'market', 'market.sql') }" )
  end

end
