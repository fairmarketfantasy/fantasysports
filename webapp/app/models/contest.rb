class Contest < ActiveRecord::Base
  belongs_to :sport
  belongs_to :market
  has_many :games
  has_many :rosters
  has_many :transaction_records
  belongs_to :owner, class_name: "User"
  belongs_to :contest_type

  self.inheritance_column = :_type_disabled

  # TODO: decide how to represent contest type, which could be multiple types. Bitmap? Another relation?

  # after_create :create_owners_roster!
  # before_save :set_invitation_code, on: :create

  validates :owner_id, :contest_type_id, :buy_in, :market_id, presence: true

  def invite(email)
    self.save if self.new_record?
    ContestMailer.invite(self, email).deliver
  end

  def submit_roster(roster)
    raise "Only in progress rosters may be submitted" unless roster.state != 'in_progress'
    Contest.transaction do
      roster.state = 'submitted'
      # we dock the balance on roster create now
      # roster.owner.customer_object.decrease_balance(roster.buy_in, 'buy_in')
      roster.save!
    end
  end

  #creates a roster for the owner and creates an invitation code
  def make_private
    set_invitation_code
    create_owners_roster!
  end

  private

    def set_invitation_code
      self.invitation_code = SecureRandom.urlsafe_base64
    end

    def create_owners_roster!
      Roster.generate(owner, contest_type)
    end

end
