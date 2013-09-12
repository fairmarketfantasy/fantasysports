class MarketOrder < ActiveRecord::Base
  belongs_to :roster

  # stubs
  def self.buy_player(roster, player)
    execSqlFunc do
      self.find_by_sql("SELECT * from buy(#{roster.id}, #{player.id})")[0]
    end
  end

  # stubs
  def self.sell_player(roster, player)
    execSqlFunc do
      self.find_by_sql("SELECT * from sell(#{roster.id}, #{player.id})")[0]
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
      case 
        when e.message =~ /sufficient funds/
          msg = "You don't have enough money to buy that player"
        else
          msg = e.message
       end
      raise HttpException.new(409, msg)
    end
  end
end
