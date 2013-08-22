class MarketOrder < ActiveRecord::Base

  # stubs
  def self.buy_player(roster, player)
    execSqlFunc do
      self.find_by_sql("SELECT * from buy(#{roster.id}, #{player.id})")[0]
    end
  end

  # stubs
  def self.sell_player(roster, player)
    execSqlFunc do
      self.find_by_sql("SELECT sell(#{roster.id}, #{player.id})")[0]
    end
  end

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

  protected

  def self.execSqlFunc
    begin
      yield
    rescue ActiveRecord::StatementInvalid => e
       # TODO: clean up error handling
      raise HttpException.new(409, e.message)
    end
  end
end
