class Contest < ActiveRecord::Base
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User", foreign_key: :owner
  belongs_to :contest_type

  TYPES = {
    "100k" => [{buy_in: 10, team_limit: 10000}],
    "970" => [
        {buy_in: 0, team_limit: 10},
        {buy_in: 2, team_limit: 10},
        {buy_in: 10, team_limit: 10},
        ],
    "194" => [
        {buy_in: 0, team_limit: 50},
        {buy_in: 2, team_limit: 50},
        {buy_in: 10, team_limit: 50},
        ],
    "h2h" => [
        {buy_in: 5, team_limit: 2},
        {buy_in: 10, team_limit: 2},
        ],
  }

  self.inheritance_column = :_type_disabled

  # TODO: decide how to represent contest type, which could be multiple types. Bitmap? Another relation?

  after_create :create_owners_roster!
  before_save :set_invitation_code, on: :create

  validates :owner, :type, :buy_in, :market_id, presence: true

  def self.valid_contest?(type, buy_in)
    TYPES[type].select{|h| h['buy_in'] == buy_in}
  end

  def invite(email)
    ContestMailer.invite(self, email).deliver
  end

  def submit_roster(roster)
    raise "Only in progress rosters may be submitted" unless roster.state != 'in_progress'
    Contest.transaction do
      roster.state = 'submitted'
      roster.owner.customer_object.decrease_balance(roster.buy_in, 'buy_in')
      roster.save!
    end
  end

  private

    def create_owners_roster!
      Roster.generate_contest_roster(owner, market, type, buy_in)
    end

    def set_invitation_code
      self.invitation_code = SecureRandom.urlsafe_base64
    end
end
