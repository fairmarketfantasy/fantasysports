class MarketOrder < ActiveRecord::Base

  # stubs
  def self.buy_player(roster, player)
    order = self.connection.execute("SELECT buy(#{roster.id}, #{player.id})")
    Rails.logger.debug(order)
    return market_order
  end

  # stubs
  def self.sell_player(roster, player)
    order = self.connection.execute("SELECT sell(#{roster.id}, #{player.id})")
    Rails.logger.debug(order)
    return market_order
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
end
