class MarketOrder < ActiveRecord::Base
  belongs_to :roster

  # THIS IS A UTILITY FUNCTION, DO NOT CALL IT FROM THE APPLICATION
  def self.load_sql_functions
    self.load_sql_file File.join(Rails.root, '..', 'market', 'market.sql')
  end

end
