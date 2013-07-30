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
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "games", force: true do |t|
    t.integer  "home_team_id", null: false
    t.integer  "away_team_id", null: false
    t.date     "game_day",     null: false
    t.datetime "game_time",    null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "games", ["game_time"], name: "index_games_on_game_time", using: :btree
  add_index "games", ["home_team_id", "away_team_id", "game_day"], name: "index_games_on_home_team_id_and_away_team_id_and_game_day", unique: true, using: :btree

  create_table "players", force: true do |t|
    t.integer  "sport_id"
    t.integer  "team_id"
    t.decimal  "point_per_game"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "sports", force: true do |t|
    t.string   "name",       null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sports", ["name"], name: "index_sports_on_name", unique: true, using: :btree

  create_table "stat_events", force: true do |t|
    t.integer  "player_id",         null: false
    t.integer  "game_id",           null: false
    t.decimal  "point_value",       null: false
    t.string   "event_description", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "teams", force: true do |t|
    t.integer  "sport_id",   null: false
    t.string   "name",       null: false
    t.string   "state"
    t.string   "country"
    t.decimal  "lat"
    t.decimal  "long"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", force: true do |t|
    t.string   "name",       null: false
    t.string   "email",      null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
