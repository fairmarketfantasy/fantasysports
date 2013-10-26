class RosterSerializer < ActiveModel::Serializer
  attributes :id, 
      :owner_id, 
      :owner_name, # include whole object?
      :market_id, 
      :state, 
      :contest_id, 
      :buy_in, 
      :remaining_salary, 
      :score, 
      :contest_rank, 
      :contest_rank_payout, 
      :amount_paid, 
      :paid_at, 
      :cancelled_cause, 
      :cancelled_at, 
      :positions,
      :started_at,
      :next_game_time,
      :live

  has_one :contest
  has_one :contest_type
  has_many :players

  def players
    @players ||= object.players_with_prices
  end

  def live
    object.live?
  end

  def owner_name
    if object.is_generated?
      @@system_usernames[object.id % @@system_usernames.length]
    else
      object.owner.username
    end
  end

  def contest_rank_payout
    if object.contest_rank
      object.contest_type.payout_for_rank(object.contest_rank)
    else
      nil
    end
  end

  @@system_usernames = %w(
teetriceps
basegear
dartboardmoorhen
sticknumerous
bocceon
matspoiled
hoopsponge
unicyclistchinese
javelinchangeable
playingthumb
polesnot
surfingwashing
targetllama
billiardshandy
surfertight
paddleballwabbit
waterskielastic
judopickled
somersaultbacon
basketballbank
cyclehippopotamus
hurdlego
volleyburning
canoeingpebbly
iceskatesrow
throwingremuda
swimpoised
boulesvroom
pitchoakwood
battinglancashire
goalgrit
swimmingtree
helmetpopper
relaytasty
fieldcyandye
skiingcapricious
wetsuitweary
bowlingbrakes
guardbullocks
highjumpfemur
slalomquizzical
olympicsneedle
fencingsnap
skierindian
frisbeezip
fielderchicken
vaultingmoldovan
malletangry
leagueberserk
squadhandball
woodcockpentathlon
campfireunicyclist
panswaterpolo
chickenspitcher
hootenannyfielding
rafflekarate
ischampion
hazardollie
bugswinning
packride
sweetcornboomerang
coordinatorhardball
stringkickball
lyricalmouthguard
forkdiver
ibistennis
capillariescycle
tighthitter
curtainsoutfielder
expertswimming
instinctivegoal
driftuniform
roomywicket
deadepee
veinicerink
somersaultrink
itchmallet
furnacelose
cuttinggoldmedal
disgustedaerobics
mildpool
poofmat
blastquarter
tonicshotput
namibianpaddle
thighpaintball
uncoveredbobsleigh
vitreousjumper
tentlacrosse
ligamentcanoeing
memorygymnastics
licketysplittarget
majorvaulting
diamondswim
scornfulteammate
secondhandracing
barkingathletics
drumskate
puddingquiver
  )
end
