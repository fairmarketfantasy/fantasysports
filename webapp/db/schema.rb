# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20130809221555) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "contests", force: true do |t|
    t.integer  "owner",      null: false
    t.string   "type",       null: false
    t.integer  "buy_in",     null: false
    t.integer  "user_cap"
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "market_id",  null: false
  end

  add_index "contests", ["market_id"], name: "index_contests_on_market_id", using: :btree

  create_table "game_events", force: true do |t|
    t.string   "stats_id"
    t.integer  "sequence_number", null: false
    t.string   "type",            null: false
    t.string   "summary",         null: false
    t.string   "clock",           null: false
    t.text     "data"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "game_stats_id",   null: false
    t.string   "acting_team"
  end

  add_index "game_events", ["game_stats_id", "sequence_number"], name: "index_game_events_on_game_stats_id_and_sequence_number", unique: true, using: :btree
  add_index "game_events", ["game_stats_id"], name: "index_game_events_on_game_stats_id", using: :btree
  add_index "game_events", ["sequence_number"], name: "index_game_events_on_sequence_number", using: :btree

  create_table "games", force: true do |t|
    t.string   "stats_id",    null: false
    t.string   "status",      null: false
    t.date     "game_day",    null: false
    t.datetime "game_time",   null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "home_team",   null: false
    t.string   "away_team",   null: false
    t.string   "season_type"
    t.integer  "season_week"
    t.integer  "season_year"
    t.string   "network"
  end

  add_index "games", ["game_day"], name: "index_games_on_game_day", using: :btree
  add_index "games", ["game_time"], name: "index_games_on_game_time", using: :btree
  add_index "games", ["stats_id"], name: "index_games_on_stats_id", unique: true, using: :btree

  create_table "market_orders", force: true do |t|
    t.integer  "market_id",       null: false
    t.integer  "contest_id",      null: false
    t.integer  "roster_id",       null: false
    t.string   "action",          null: false
    t.integer  "player_id",       null: false
    t.decimal  "price",           null: false
    t.boolean  "rejected"
    t.string   "rejected_reason"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "market_players", force: true do |t|
    t.integer "market_id",     null: false
    t.integer "player_id",     null: false
    t.decimal "initial_price", null: false
  end

  add_index "market_players", ["player_id", "market_id"], name: "index_market_players_on_player_id_and_market_id", unique: true, using: :btree

  create_table "markets", force: true do |t|
    t.string   "name"
    t.integer  "shadow_bets",     null: false
    t.integer  "shadow_bet_rate", null: false
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "exposed_at",      null: false
  end

  create_table "players", force: true do |t|
    t.string   "stats_id"
    t.integer  "sport_id"
    t.integer  "team_id"
    t.string   "name"
    t.string   "name_abbr"
    t.string   "birthdate"
    t.integer  "height"
    t.integer  "weight"
    t.string   "college"
    t.string   "position"
    t.integer  "jersey_number"
    t.string   "status"
    t.integer  "total_games",   default: 0, null: false
    t.integer  "total_points",  default: 0, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "players", ["stats_id"], name: "index_players_on_stats_id", unique: true, using: :btree
  add_index "players", ["team_id"], name: "index_players_on_team_id", using: :btree

  create_table "rosters", force: true do |t|
    t.integer  "owner_id",                         null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "market_id",                        null: false
    t.integer  "contest_id",                       null: false
    t.integer  "buy_in",                           null: false
    t.decimal  "remaining_salary",                 null: false
    t.boolean  "is_valid",         default: false, null: false
    t.integer  "final_points"
    t.integer  "finish_place"
    t.decimal  "amount_paid"
    t.datetime "paid_at"
    t.boolean  "cancelled",        default: false, null: false
    t.string   "cancelled_cause"
    t.datetime "cancelled_at"
  end

  add_index "rosters", ["cancelled"], name: "index_rosters_on_cancelled", using: :btree
  add_index "rosters", ["contest_id"], name: "index_rosters_on_contest_id", using: :btree
  add_index "rosters", ["market_id"], name: "index_rosters_on_market_id", using: :btree

  create_table "rosters_players", force: true do |t|
    t.integer "player_id",         null: false
    t.integer "contest_roster_id", null: false
  end

  add_index "rosters_players", ["player_id", "contest_roster_id"], name: "contest_rosters_players_index", unique: true, using: :btree

  create_table "sports", force: true do |t|
    t.string   "name",       null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sports", ["name"], name: "index_sports_on_name", unique: true, using: :btree

  create_table "stat_events", force: true do |t|
    t.string   "type",                null: false
    t.text     "data",                null: false
    t.string   "point_type",          null: false
    t.decimal  "point_value",         null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "player_stats_id",     null: false
    t.string   "game_stats_id",       null: false
    t.string   "game_event_stats_id", null: false
  end

  add_index "stat_events", ["game_stats_id"], name: "index_stat_events_on_game_stats_id", using: :btree
  add_index "stat_events", ["player_stats_id", "game_event_stats_id", "type"], name: "unique_stat_events", unique: true, using: :btree

  create_table "teams", force: true do |t|
    t.integer  "sport_id",   null: false
    t.string   "abbrev",     null: false
    t.string   "name",       null: false
    t.string   "conference", null: false
    t.string   "division",   null: false
    t.string   "market"
    t.string   "state"
    t.string   "country"
    t.decimal  "lat"
    t.decimal  "long"
    t.text     "standings"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "teams", ["abbrev", "sport_id"], name: "index_teams_on_abbrev_and_sport_id", unique: true, using: :btree
  add_index "teams", ["abbrev"], name: "index_teams_on_abbrev", using: :btree

  create_table "users", force: true do |t|
    t.string   "name",                                null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.string   "provider"
    t.string   "uid"
    t.string   "confirmation_token"
    t.datetime "confirmed_at"
    t.string   "unconfirmed_email"
    t.datetime "confirmation_sent_at"
  end

  add_index "users", ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true, using: :btree
  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree

  create_table "venues", force: true do |t|
    t.string "stats_id"
    t.string "country"
    t.string "state"
    t.string "city"
    t.string "type"
    t.string "name"
    t.string "surface"
  end

  add_index "venues", ["stats_id"], name: "index_venues_on_stats_id", using: :btree

end
