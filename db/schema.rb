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

ActiveRecord::Schema.define(version: 20130730000647) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "contest_rosters", force: true do |t|
    t.integer  "owner_id",   null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "contest_rosters_players", force: true do |t|
    t.integer "player_id",         null: false
    t.integer "contest_roster_id", null: false
  end

  add_index "contest_rosters_players", ["player_id", "contest_roster_id"], name: "contest_rosters_players_index", unique: true, using: :btree

  create_table "contests", force: true do |t|
    t.integer  "owner",      null: false
    t.string   "type",       null: false
    t.integer  "buy_in",     null: false
    t.integer  "user_cap"
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "game_events", force: true do |t|
    t.string   "stats_id"
    t.string   "sequence_number", null: false
    t.integer  "game_id",         null: false
    t.string   "type",            null: false
    t.string   "summary",         null: false
    t.string   "clock",           null: false
    t.text     "data"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "game_events", ["game_id"], name: "index_game_events_on_game_id", using: :btree
  add_index "game_events", ["sequence_number"], name: "index_game_events_on_sequence_number", using: :btree
  add_index "game_events", ["stats_id"], name: "index_game_events_on_stats_id", using: :btree

  create_table "games", force: true do |t|
    t.string   "stats_id",     null: false
    t.integer  "home_team_id", null: false
    t.integer  "away_team_id", null: false
    t.string   "status",       null: false
    t.date     "game_day",     null: false
    t.datetime "game_time",    null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "games", ["game_day"], name: "index_games_on_game_day", using: :btree
  add_index "games", ["game_time"], name: "index_games_on_game_time", using: :btree
  add_index "games", ["home_team_id", "away_team_id", "game_day"], name: "index_games_on_home_team_id_and_away_team_id_and_game_day", unique: true, using: :btree
  add_index "games", ["stats_id"], name: "index_games_on_stats_id", using: :btree

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
    t.string   "salary"
    t.integer  "total_games",     default: 0, null: false
    t.integer  "total_points",    default: 0, null: false
    t.decimal  "points_per_game"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "players", ["points_per_game"], name: "index_players_on_points_per_game", using: :btree
  add_index "players", ["stats_id"], name: "index_players_on_stats_id", using: :btree
  add_index "players", ["team_id"], name: "index_players_on_team_id", using: :btree

  create_table "sports", force: true do |t|
    t.string   "name",       null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sports", ["name"], name: "index_sports_on_name", unique: true, using: :btree

  create_table "stat_events", force: true do |t|
    t.integer "game_id",       null: false
    t.integer "game_event_id", null: false
    t.integer "player_id",     null: false
    t.string  "type",          null: false
    t.text    "data",          null: false
    t.string  "point_type",    null: false
    t.decimal "point_value",   null: false
  end

  add_index "stat_events", ["game_event_id"], name: "index_stat_events_on_game_event_id", using: :btree
  add_index "stat_events", ["game_id"], name: "index_stat_events_on_game_id", using: :btree

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

  add_index "teams", ["abbrev"], name: "index_teams_on_abbrev", using: :btree

  create_table "users", force: true do |t|
    t.string   "name",       null: false
    t.string   "email",      null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "users", ["email"], name: "index_users_on_email", using: :btree

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
