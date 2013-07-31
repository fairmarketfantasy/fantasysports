class CreateStatEvents < ActiveRecord::Migration
  def change
=begin
  passing: 
    att: attempt 
    cmp: completion 
    yds: yards 
    sk_yds: sacked yards lost
    td: touchdown
    int: interception
    fd: first down
    sfty: tackled for safety
    rz_att: red zone attempt

  receiving: 
    tar: target
    rec: receptions
    yds: total yards
    yac: yards after completion
    td: touchdown
    fum: fumbled on reception
    fd: first down
    rz_tar: red zone target


  rushing:
    att: attempts
    fd: first down
    fum: fumbled on rush
    rz_att: red zone attempt
    sfty: tackled for safety
    yds: total yards
    td: touchdown

  defense:
    tackle: tackle
    ast: assist
    sack: sack
    tlost: tackle for a loss
    sack_yds: sack yards
    sfty: safety
    int: interception
    force_fum: forced fumble

  penalty:
    fd: first down
    yds: yards
    abbr: abbreviation - 
      dtm: 12 men in huddle
      d12: 12 players
      dpb: Batting or punching loose ball
      dnc: Captains not appearing for coin toss
      dcw: Clipping
      dds: Delay of game at start of half
      ddg: Delay of game
      ddk: Delay of kickoff
      den: Encroachment
      dec: Excessive crowd noise
      det: Excessive time outs
      dfm: Facemask incidental
      dgf: Facemasking ball carrier or quarterback
      daf: Facemasking
      dfi: Fair catch interference
      dfo: Helmet off
      dsp: Helmet to butt spear or ram
      duh: Holding
      dih: Illegal use of hands
      dhc: Horse collar
      dic: Illegal Contact
      dib: Illegal block in the back
      dif: Illegal formation
      dlb: Illegal low block
      dkb: Kicking a loose ball
      dko: Kicking or kneeing opponent
      dlp: Leaping
      dlv: Leverage
      dnz: Neutral zone infraction
      dof: Offside
      dpu: Palpably unfair act
      dpi: Pass interference
      dpf: Personal foul
      dpo: Piling on
      dob: Player out of bounds at snap
      drc: Roughing the kicker
      drp: Roughing the passer
      dhk: Running into kicker
      dso: Striking opponent on head or neck
      dsf: Striking opponent with fist
      dho: Striking or shoving a game official
      dtn: Taunting
      dla: Team's late arrival on the field prior to scheduled kickoff
      dtr: Tripping
      dur: Unnecessary roughness
      duc: Unsportsmanlike conduct
      dhw: Using a helmet as a weapon
      dth: Using top of helmet unnecessarily
      ddq: Defensive disqualification
      otm: 12 men in the huddle
      o12: 12 players
      ol7: Less than seven men on offensive line
      ofr: A punter placekicker or holder who fakes being roughed
      onc: Captains not appearing at coin toss
      ocb: Chop block
      ocw: Clipping
      ods: Delay of game at start of half
      odg: Delay of game
      odk: Delay of kickoff
      oec: Excessive crowd noise
      oet: Excessive time outs
      ofm: Facemask incidental
      oaf: Facemasking
      ore: Failure to report change of eligibility
      ofs: False start
      ooo: First onside kickoff out of bounds
      ofo: Helmet off
      ofk: Offside on free kick
      osp: Helmet to butt spear or ram
      ohr: Helping the runner
      ouh: Holding
      oih: Illegal use of hands
      ohc: Horse collar
      ops: Illegal forward pass
      opb: Forward pass thrown from beyond line of scrimmage
      oip: Illegal procedure
      oic: oic: Illegal crackback block by offense
      oif: Illegal formation
      olb: Illegal low block
      oim: Illegal motion
      oir: Illegal return
      ois: Illegal shift
      oiu: Illegal substitution
      oid: Ineligible member kicking team beyond scrimmage
      opd: Ineligible player downfield during passing down
      oig: Intentional grounding
      ofc: Invalid fair catch signal
      okb: Kicking a loose ball
      okk: Kicking or kneeing opponent
      oko: Kicking team player out of bounds
      olp: Leaping
      olv: Leverage
      onz: Neutral zone infraction
      oof: Offside
      opu: Palpably unfair act
      opi: Pass interference
      oto: Pass touched by receiver who went OOB
      ori: Pass touched or caught by ineligible receiver
      opf: Personal foul
      opo: Piling on
      oob: Player out of bounds at snap
      oso: Striking opponent on head or neck
      osf: Striking opponent with fist
      oho: Striking or shoving a game official
      otn: Taunting
      ola: Team's late arrival on the field prior to scheduled kickoff
      otr: Tripping
      our: Unnecessary roughness
      ouc: Unsportsmanlike conduct
      ohw: Using a helmet as a weapon
      oth: Using top of helmet unnecessarily
      oit: Illegal touch kick
      odq: Offensive disqualification
=end

    create_table :stat_events do |t|
      t.integer :game_id, :null => false
      t.integer :game_event_id, :null => false
      t.integer :player_id, :null => false
      t.string :type, :null => false
      t.text :data, :null => false # Some combination of the above
      t.string :point_type, :null => false
      t.decimal :point_value, :null => false
    end
    add_index :stat_events, :game_id
    add_index :stat_events, :game_event_id

    create_table :game_events do |t|
      t.string :stats_id
      t.string :sequence_number, :null => false
      t.integer :game_id, :null => false
      t.string :type, :null => false
      t.string :summary, :null => false
      t.string :clock, :null => false
      t.text :data
      t.timestamps
    end
    add_index :game_events, :game_id
    add_index :game_events, :stats_id
    add_index :game_events, :sequence_number
  end
end
