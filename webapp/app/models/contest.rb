class Contest < ActiveRecord::Base
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User", foreign_key: :owner

  self.inheritance_column = :_type_disabled

  # TODO: decide how to represent contest type, which could be multiple types. Bitmap? Another relation?

  after_create :create_owners_roster!
  before_save :set_invitation_code, on: :create

  validates :owner, :type, :buy_in, :market_id, presence: true

  def invite(email)
    ContestMailer.invite(self, email).deliver
  end

  private

    def create_owners_roster!
      Roster.new_contest_roster(owner, self)
    end

    def set_invitation_code
      self.invitation_code = SecureRandom.urlsafe_base64
    end
end
