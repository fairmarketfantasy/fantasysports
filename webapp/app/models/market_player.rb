class MarketPlayer < ActiveRecord::Base
  belongs_to :market
  belongs_to :player
end

