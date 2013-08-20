class Contest < ActiveRecord::Base
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User", foreign_key: :owner

  # TODO: decide how to represent contest type, which could be multiple types. Bitmap? Another relation?

  after_create :create_owners_roster!
  before_save :set_invitation_code, on: :create

  validates :owner, :type, :buy_in, :market_id, presence: true

  def invite(email)
    ContestMailer.invite(self, email).deliver
  end

  private

    def create_owners_roster!
      owner.contest_rosters.create!(  market_id:        market_id,
                                      contest_id:       id,
                                      buy_in:           buy_in,
                                      contest_type:     type,
                                      state:            "in_progress"
                                        )
    end

    def set_invitation_code
      self.invitation_code = SecureRandom.urlsafe_base64
    end
end
