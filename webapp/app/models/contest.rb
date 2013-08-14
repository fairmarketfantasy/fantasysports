class Contest < ActiveRecord::Base
  #because we have a column named "type" ActiveRecord gets all cute and tries to think
  #we are doing Single Table Inheritace, however we are not so lets just tell Active Record
  #to not use the type column and instead tell our inheritance column is something that doesn't exist
  self.inheritance_column = :_type_disabled

  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  belongs_to :owner, class_name: "User", foreign_key: :owner

  # TODO: decide how to represent contest type, which could be multiple types. Bitmap? Another relation?

  after_create :create_owners_roster!

  validates :owner, :type, :buy_in, :market_id, presence: true

  private

    def create_owners_roster!
      owner.contest_rosters.create!(  market_id:        market_id,
                                      contest_id:       id,
                                      buy_in:           buy_in
                                        )
    end
end
