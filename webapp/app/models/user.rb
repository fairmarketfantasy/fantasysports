class User < ActiveRecord::Base

  mount_uploader :avatar, AvatarUploader

  TOKEN_SKUS = {
    '1000'  => { :tokens => 1000,  :cost => 500},
    '2000'  => { :tokens => 2000,  :cost => 1000},
    '5000' => {:tokens => 5000,  :cost => 2500},
  }
  #attr_protected :admin, :email, :password
  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  devise :oauth2_providable,
         :oauth2_facebook_grantable,
         :oauth2_password_grantable,
         :oauth2_refresh_token_grantable,
         :oauth2_authorization_code_grantable,
         :database_authenticatable, :registerable, :confirmable,
         :recoverable, :rememberable, :trackable, :validatable
  devise :omniauthable, :omniauth_providers => [:facebook, :facebook_access_token]

  attr_accessor :current_password
  attr_accessor :amount, :bets, :winnings, :total_wins, :total_losses # Leaderboard keys

  attr_accessible :name, :username, :provider, :uid, :fb_token, :unconfirmed_email, :image_url, :takes_tokens,
      :email, :current_password, :password, :password_confirmation, :remember_me, :first_name,
      :last_name, :privacy, :accepted_privacy_at, :agreed_to_sync, :inviter_id, :avatar, :avatar_cache, :remove_avatar

  has_many :rosters, foreign_key: :owner_id
  has_many :contests, foreign_key: :owner_id
  has_many :push_devices
  has_many :individual_predictions
  has_many :transaction_records
  has_many :league_memberships
  has_many :leagues, :through => :league_memberships
  has_one  :customer_object
  has_one  :recipient
  belongs_to :inviter, :class_name => 'User'

  before_create :set_blank_name
  after_create :create_customer_object

  def set_blank_name
    self.name ||= ''
  end

  def active_account?
    customer_object.has_agreed_terms? && customer_object.is_active? &&
      !customer_object.locked? || self.id == SYSTEM_USER.id ||
      customer_object.trial_active?
  end

  def create_customer_object
    CustomerObject.create!(:user_id => self.id)
  end

  def self.find_for_facebook_oauth(auth)
    Rails.logger.debug(auth.pretty_inspect)
    user = User.find_by(email: auth.info.email) || User.where(uid: auth.uid, provider: auth.provider, fb_token: auth.credentials.token).first_or_initialize
    # Re-set these parameters in case we're using a new auth method
    user.email = auth.info.email
    user.provider = auth.provider
    user.uid = auth.uid
    user.fb_token = auth.credentials.token
    user.name = auth.extra.raw_info.name
    user.image_url = auth.info.image.gsub('http', 'https')
    if user.encrypted_password.blank?
      user.password = Devise.friendly_token[0,20]
    end
    user.save!
    user
  end

  def confirmation_required?
    false
  end

  def email
    self[:email].blank? ? self.unconfirmed_email : self[:email]
  end

  def referral_code
    if self[:referral_code].nil?
      self.referral_code = SecureRandom.hex(16)
      self.save!
    end
    super
  end

  def image_url
    #avatar    (from upload: AvatarUploader)
    #image_url (from facebook)
    if self.avatar.presence
      self.avatar.url
    elsif self[:image_url].presence
      self[:image_url]
    else
      ActionController::Base.helpers.image_path('default-user.png')
    end
  end

  def in_progress_roster
    rosters.where(:state => 'in_progress').first
  end

  # NOENTRY TODO: change to count entries
  def charge(type, amount, opts = {}) # roster_id, contest_id, invitation_id, referred_id
    case type.to_sym
    when :balance
      self.customer_object.decrease_account_balance(amount, opts)
    when :monthly_entry
      self.customer_object.increase_monthly_contest_entries!(amount, opts)
    when :monthly_winnings
      self.customer_object.decrease_monthly_winnings(amount, opts)
    else
      raise "Type must be one of [balance, monthly_entry, monthly_winnings]" unless [:balance, :monthly_entry, :monthly_winnings].include?(type.to_sym)
    end
  end

  def payout(type, amount, opts)
    case type.to_sym
    when :balance
      self.customer_object.increase_account_balance(amount, opts)
    when :monthly_entry
      self.customer_object.decrease_monthly_contest_entries!(amount, opts)
    when :monthly_winnings
      self.customer_object.increase_monthly_winnings(amount, opts)
    else
      raise "Type must be one of [balance, monthly_entry, monthly_winnings]"
    end
  end

  def abridged? # Used in api serializer as scope
    false
  end

  def last_sent_digest_at
    se = SentEmail.where(:user_id => self.id).order('created_at desc').first
    se ? se.created_at : Time.new(1900) # long ago
  end

  SYSTEM_USERNAMES = [
"teetriceps",
"basegear",
"dartboardmoorhen",
"sticknumerous",
"bocceon",
"matspoiled",
"hoopsponge",
"unicyclistchinese",
"javelinchange",
"playingthumb",
"polesnot",
"surfingwashing",
"targetllama",
"billiardshandy",
"surfertight",
"paddleballwabbit",
"waterskielastic",
"judopickled",
"somersaultbacon",
"basketballbank",
"cyclehippo",
"hurdlego",
"volleyburning",
"canoeingpebbly",
"iceskatesrow",
"throwingremuda",
"swimpoised",
"boulesvroom",
"pitchoakwood",
"battingblancas",
"goalgrit",
"swimmingtree",
"helmetpopper",
"relaytasty",
"fieldcyandye",
"skiingcapricious",
"wetsuitweary",
"bowlingbrakes",
"guardbullocks",
"highjumpfemur",
"slalomquizzical",
"olympicsneedle",
"fencingsnap",
"skierindian",
"frisbeezip",
"fielderchicken",
"vaultingmoldovan",
"malletangry",
"leagueberserk",
"squadhandball",
"woodcockpentathlon",
"campfireunicyclist",
"panswaterpolo",
"chickenspitcher",
"hootenannyfielding",
"rafflekarate",
"ischampion",
"hazardollie",
"bugswinning",
"packride",
"sweetboomerang",
"coordinatorhardball",
"stringkickball",
"lyricalmouthguard",
"forkdiver",
"ibistennis",
"capillariescycle",
"tighthitter",
"curtainsoutfielder",
"expertswimming",
"instinctivegoal",
"driftuniform",
"roomywicket",
"deadepee",
"veinicerink",
"somersaultrink",
"itchmallet",
"furnacelose",
"cuttinggoldmedal",
"disgustedaerobics",
"mildpool",
"poofmat",
"blastquarter",
"tonicshotput",
"namibianpaddle",
"thighpaintball",
"uncoveredbobsleigh",
"vitreousjumper",
"tentlacrosse",
"ligamentcanoeing",
"memorygymnastics",
"licketysplittarget",
"majorvaulting",
"diamondswim",
"scornfulteammate",
"secondhandracing",
"barkingathletics",
"drumskate",
"puddingquiver",
"oysterswordfish",
"mutationparrot",
"complexsheep",
"chatteringpartridge",
"swiftcommittee",
"pandemoniumpup",
"cacheswan",
"paradewoodpecker",
"corpsbuffalo",
"hosthart",
"movementinsect",
"intrigueperegrine",
"optimismgull",
"implausibilebacteria",
"gagglehorse",
"thoughtpeacock",
"picketcoot",
"talentponie",
"twinklefalcon",
"erstbittern",
"hedgegoshawk",
"rangaleauk",
"hatchcrane",
"classpoultry",
"herdostrich",
"pitchicken",
"roperhinoceros",
"flicksnake",
"dogfishness",
"descentgiraffe",
"bindiguana",
"fraidape",
"auditfox",
"libraryroach",
"quivervole",
"boardjackrabbit",
"doutdunbird",
"quarrelgreyhound",
"stubbornnessclam",
"worshipmoorhen",
"crewstork",
"grovewaterfowl",
"rabbleredwings",
"wrackmoose",
"subtletyruffs",
"bavinhog",
"amberelk",
"jonquilflamingo",
"prussianblues",
"jadebadger",
"champagnepolarbear",
"whitehinds",
"silverturtle",
"azurevulture",
"raspberrygnat",
"apricotdunbird",
"lemonfinch",
"maroonbloodhound",
"copperconie",
"ceruleanzebra",
"springbudgrouse",
"turquoisemallard",
"periwinkleplover",
"redvioletgerbil",
"crimsonpup",
"thrattlesnake",
"tanmonkey",
"cerisevole",
"electricblueibexe",
"burgundystoat",
"redshrimp",
"salmonpenguin",
"limemole",
"blueviper",
"turtledove",
"taupewidgeon",
"peachgrasshopper",
"lilacotter",
"babyblue",
"sapphiretarmigan",
"olivebass",
"springgreen",
"roseteal",
"orchidflygraybat",
"pearinsect",
"yellowbarracuda",
"harlequinangelfish",
"plumrainbow",
"cyanbittern",
"beigemare",
"byzantiumracehorse",
"orangecaribou",
"downlutz",
"lazyuniform",
"euphoricmoves",
"pickleball",
"discouraged",
"insecurediamond",
"needybaseball",
"humiliatedbiathlon",
"madsurfer",
"sexyboomerang",
"passionatebob",
"arenaobsessed",
"crazyfreethrow",
"hatefulhalftime",
"jadedwalk",
"wincollector",
"emptykingfu",
"iratesledding",
"cruelplayer",
"grouchyrink",
"satisfiedollie",
"angrydugout",
"homesickscull",
"frazzledloser",
"confusedtarget",
"ecstaticgymnast",
"excitedhighjump",
"hopelessfield",
"abandonedrower",
"grudgingrelay",
"enragedkneepads",
"lustfulinfield",
"mercifulwaterskier",
"disheartenedhomerun",
"contemptuousgame",
"distressedfitness",
"hurtcricket",
"goofyaerobics",
"bluetennis",
"warmbilliards",
"joyfulkayaker",
"ardentshotput",
"possessivejog",
"thrilledcue",
"sensualboxer",
"panickysoccer",
"vengefularcher",
"delightedbat",
"expectantbow",
"A-1 Benchmen Bricks",
"Their Potatoes",
"Milwaukee Dodgers",
"Robert Whales",
"Wonder Ufoed",
"Crawlers",
"Pierced Horns",
"Twisters Caps",
"Simpletons",
"Cool Garage",
"Tender Counts",
"Virginia David",
"Fab E-Lemon-Ators",
"Ba-Da-Bing Now",
"Twelve Trucks",
"Lighting Teamwork",
"Antti's Usuals Wigglers",
"Civil Touch",
"Village Dusters",
"Sweat Wheel Hawks",
"Horsemen Bears",
"Sticky Stunts",
"Boilers",
"Fighting The Zone",
"Brock Babes",
"Weak Furry",
"Freak Brothers",
"Pierced Hop",
"GuyLayers",
"Femmes",
"Clear Atomic",
"Karma Chimps",
"Simpletons",
"Best Sand Wigglers",
"Monte Crawdads Bears",
"Beavis Foxtrot",
"Presidents",
"Riff Answer",
"Equator Saturns",
"Doctors Rags",
"Not Elite",
"Jerry's Mountain",
"Slutty Barbarians",
"Satellite Boys",
"Nuff Cheetahs",
"Son Slice",
"Net Whip",
"Solar Reality",
"Catch Alls",
"Les Senators",
"Case Usa",
"Bud World",
"Ripley's Labyrinth",
"Cutting Stealheads",
"Yellow Encores",
"Onion Creation",
"Snow Chimps",
"Mass Your Knees",
"Wicked City",
"Lawn Cavalry",
"Delayed Momentum",
"Leznerf Pistons",
"Deadly Awe",
"Rocket Valkyries",
"Oh! Walkers",
"Hard Champs",
"Post Hoosiers",
"5 Dancers",
"Phantom Plus One",
"Sizzle And Miss",
"Kule Projectiles",
"She Skelter",
"Free Saturn",
"10 Moon Bears",
"Labatt's Dreams",
"Triangle Aggies",
"Passing Earth ",
"Federation Dudes",
"East Egrets",
"Hideous Browns",
"2k Snakes",
"151 Party",
"Blockbusters",
"Pocahontas",
"Troglodytes",
"Boys Nuts",
"Akron Outbreak",
"Illegal Browns",
"Snow Kelts",
"Rockers",
"Old Crash",
"Caught Ocean",
"Some Stallions",
"Strike Hornettes",
"Roadrunner",
"Eliminators",
"Wet Eventually",
"Ramona's Explosion",
"Paul's Freaks",
"Miracle Sharp",
"Hoop Quakers",
"Hang Lemons",
"Fly for Pedro",
"Forest Geeks",
"Breakfast Muskies",
]
end
