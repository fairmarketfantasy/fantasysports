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

ActiveRecord::Schema.define(version: 20131202204307) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admin_users", force: true do |t|
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "admin_users", ["email"], name: "index_admin_users_on_email", unique: true, using: :btree
  add_index "admin_users", ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true, using: :btree

  create_table "contest_types", force: true do |t|
    t.integer "market_id",                          null: false
    t.string  "name",                               null: false
    t.text    "description"
    t.integer "max_entries",                        null: false
    t.integer "buy_in",                             null: false
    t.decimal "rake",                               null: false
    t.text    "payout_structure",                   null: false
    t.integer "user_id"
    t.boolean "private"
    t.integer "salary_cap"
    t.string  "payout_description", default: "",    null: false
    t.boolean "takes_tokens",       default: false
    t.integer "limit"
    t.string  "positions"
  end

  add_index "contest_types", ["market_id"], name: "index_contest_types_on_market_id", using: :btree

  create_table "contests", force: true do |t|
    t.integer  "owner_id",                        null: false
    t.integer  "buy_in",                          null: false
    t.integer  "user_cap"
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "market_id",                       null: false
    t.string   "invitation_code"
    t.integer  "contest_type_id",                 null: false
    t.integer  "num_rosters",     default: 0
    t.datetime "paid_at"
    t.boolean  "private",         default: false
    t.integer  "league_id"
    t.integer  "num_generated",   default: 0
    t.datetime "cancelled_at"
  end

  add_index "contests", ["market_id"], name: "index_contests_on_market_id", using: :btree

  create_table "credit_cards", force: true do |t|
    t.integer "customer_object_id",                  null: false
    t.boolean "deleted",             default: false, null: false
    t.string  "obscured_number"
    t.string  "first_name"
    t.string  "last_name"
    t.string  "card_type"
    t.date    "expires"
    t.string  "paypal_card_id"
    t.string  "network_merchant_id"
  end

  create_table "customer_objects", force: true do |t|
    t.integer  "user_id",                         null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "balance",         default: 0
    t.boolean  "locked",          default: false, null: false
    t.text     "locked_reason"
    t.integer  "default_card_id"
  end

  create_table "delayed_jobs", force: true do |t|
    t.integer  "priority",   default: 0, null: false
    t.integer  "attempts",   default: 0, null: false
    t.text     "handler",                null: false
    t.text     "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "delayed_jobs", ["priority", "run_at"], name: "delayed_jobs_priority", using: :btree

  create_table "email_unsubscribes", force: true do |t|
    t.string   "email",                      null: false
    t.string   "email_type", default: "all", null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

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
    t.string   "stats_id",         null: false
    t.string   "status",           null: false
    t.date     "game_day",         null: false
    t.datetime "game_time",        null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "home_team",        null: false
    t.string   "away_team",        null: false
    t.string   "season_type"
    t.integer  "season_week"
    t.integer  "season_year"
    t.string   "network"
    t.boolean  "bench_counted"
    t.datetime "bench_counted_at"
  end

  add_index "games", ["bench_counted_at"], name: "index_games_on_bench_counted_at", using: :btree
  add_index "games", ["game_day"], name: "index_games_on_game_day", using: :btree
  add_index "games", ["game_time"], name: "index_games_on_game_time", using: :btree
  add_index "games", ["stats_id"], name: "index_games_on_stats_id", unique: true, using: :btree

  create_table "games_markets", force: true do |t|
    t.string  "game_stats_id", null: false
    t.integer "market_id"
  end

  add_index "games_markets", ["market_id", "game_stats_id"], name: "index_games_markets_on_market_id_and_game_stats_id", unique: true, using: :btree

  create_table "invitations", force: true do |t|
    t.string   "email",                              null: false
    t.integer  "inviter_id",                         null: false
    t.integer  "private_contest_id"
    t.integer  "contest_type_id"
    t.string   "code",                               null: false
    t.boolean  "redeemed",           default: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "league_memberships", force: true do |t|
    t.integer  "user_id"
    t.integer  "league_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "leagues", force: true do |t|
    t.string   "name"
    t.integer  "buy_in"
    t.integer  "max_entries"
    t.integer  "salary_cap"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "takes_tokens"
    t.integer  "start_day"
    t.string   "duration"
    t.string   "identifier"
  end

  create_table "market_orders", force: true do |t|
    t.integer  "market_id",       null: false
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
    t.integer  "market_id",                           null: false
    t.integer  "player_id",                           null: false
    t.decimal  "shadow_bets"
    t.decimal  "bets",                default: 0.0
    t.datetime "locked_at"
    t.decimal  "initial_shadow_bets"
    t.boolean  "locked",              default: false
    t.integer  "score",               default: 0,     null: false
    t.string   "player_stats_id"
  end

  add_index "market_players", ["player_id", "market_id"], name: "index_market_players_on_player_id_and_market_id", unique: true, using: :btree

  create_table "markets", force: true do |t|
    t.string   "name"
    t.decimal  "shadow_bets",                       null: false
    t.decimal  "shadow_bet_rate",                   null: false
    t.datetime "opened_at"
    t.datetime "closed_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "published_at"
    t.string   "state"
    t.decimal  "total_bets"
    t.integer  "sport_id",                          null: false
    t.decimal  "initial_shadow_bets"
    t.decimal  "price_multiplier",    default: 1.0
    t.datetime "started_at"
    t.text     "fill_roster_times"
  end

  add_index "markets", ["closed_at", "started_at", "sport_id"], name: "index_markets_on_closed_at_and_started_at_and_sport_id", unique: true, using: :btree

  create_table "oauth2_access_tokens", force: true do |t|
    t.integer  "user_id"
    t.integer  "client_id"
    t.integer  "refresh_token_id"
    t.string   "token"
    t.datetime "expires_at"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "oauth2_access_tokens", ["client_id"], name: "index_oauth2_access_tokens_on_client_id", using: :btree
  add_index "oauth2_access_tokens", ["expires_at"], name: "index_oauth2_access_tokens_on_expires_at", using: :btree
  add_index "oauth2_access_tokens", ["token"], name: "index_oauth2_access_tokens_on_token", unique: true, using: :btree
  add_index "oauth2_access_tokens", ["user_id"], name: "index_oauth2_access_tokens_on_user_id", using: :btree

  create_table "oauth2_authorization_codes", force: true do |t|
    t.integer  "user_id"
    t.integer  "client_id"
    t.string   "token"
    t.datetime "expires_at"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "oauth2_authorization_codes", ["client_id"], name: "index_oauth2_authorization_codes_on_client_id", using: :btree
  add_index "oauth2_authorization_codes", ["expires_at"], name: "index_oauth2_authorization_codes_on_expires_at", using: :btree
  add_index "oauth2_authorization_codes", ["token"], name: "index_oauth2_authorization_codes_on_token", unique: true, using: :btree
  add_index "oauth2_authorization_codes", ["user_id"], name: "index_oauth2_authorization_codes_on_user_id", using: :btree

  create_table "oauth2_clients", force: true do |t|
    t.string   "name"
    t.string   "redirect_uri"
    t.string   "website"
    t.string   "identifier"
    t.string   "secret"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "oauth2_clients", ["identifier"], name: "index_oauth2_clients_on_identifier", unique: true, using: :btree

  create_table "oauth2_refresh_tokens", force: true do |t|
    t.integer  "user_id"
    t.integer  "client_id"
    t.string   "token"
    t.datetime "expires_at"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "oauth2_refresh_tokens", ["client_id"], name: "index_oauth2_refresh_tokens_on_client_id", using: :btree
  add_index "oauth2_refresh_tokens", ["expires_at"], name: "index_oauth2_refresh_tokens_on_expires_at", using: :btree
  add_index "oauth2_refresh_tokens", ["token"], name: "index_oauth2_refresh_tokens_on_token", unique: true, using: :btree
  add_index "oauth2_refresh_tokens", ["user_id"], name: "index_oauth2_refresh_tokens_on_user_id", using: :btree

  create_table "players", force: true do |t|
    t.string   "stats_id"
    t.integer  "sport_id"
    t.string   "name"
    t.string   "name_abbr"
    t.string   "birthdate"
    t.integer  "height"
    t.integer  "weight"
    t.string   "college"
    t.string   "position"
    t.integer  "jersey_number"
    t.string   "status"
    t.integer  "total_games",   default: 0,     null: false
    t.integer  "total_points",  default: 0,     null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "team"
    t.integer  "benched_games", default: 0
    t.boolean  "removed",       default: false
  end

  add_index "players", ["benched_games"], name: "index_players_on_benched_games", using: :btree
  add_index "players", ["stats_id"], name: "index_players_on_stats_id", unique: true, using: :btree
  add_index "players", ["team"], name: "index_players_on_team", using: :btree

  create_table "promo_redemptions", force: true do |t|
    t.integer  "promo_id",   null: false
    t.integer  "user_id",    null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "promo_redemptions", ["user_id", "promo_id"], name: "index_promo_redemptions_on_user_id_and_promo_id", unique: true, using: :btree

  create_table "promos", force: true do |t|
    t.string   "code",                           null: false
    t.datetime "valid_until"
    t.integer  "cents",          default: 0,     null: false
    t.integer  "tokens",         default: 0,     null: false
    t.boolean  "only_new_users", default: false, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "promos", ["code"], name: "index_promos_on_code", unique: true, using: :btree

  create_table "push_devices", force: true do |t|
    t.string   "device_id"
    t.string   "device_type"
    t.integer  "user_id"
    t.string   "token"
    t.string   "environment"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "recipients", force: true do |t|
    t.integer "user_id",      null: false
    t.string  "paypal_email", null: false
  end

  create_table "rosters", force: true do |t|
    t.integer  "owner_id",                         null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "market_id",                        null: false
    t.integer  "contest_id"
    t.integer  "buy_in",                           null: false
    t.decimal  "remaining_salary",                 null: false
    t.integer  "score"
    t.integer  "contest_rank"
    t.decimal  "amount_paid"
    t.datetime "paid_at"
    t.string   "cancelled_cause"
    t.datetime "cancelled_at"
    t.string   "state",                            null: false
    t.datetime "submitted_at"
    t.integer  "contest_type_id",  default: 0,     null: false
    t.boolean  "cancelled",        default: false
    t.integer  "wins"
    t.integer  "losses"
    t.boolean  "takes_tokens"
    t.boolean  "is_generated",     default: false
    t.integer  "bonus_points",     default: 0
    t.text     "bonuses"
    t.string   "view_code"
  end

  add_index "rosters", ["contest_id"], name: "index_rosters_on_contest_id", using: :btree
  add_index "rosters", ["contest_type_id"], name: "index_rosters_on_contest_type_id", using: :btree
  add_index "rosters", ["market_id"], name: "index_rosters_on_market_id", using: :btree
  add_index "rosters", ["submitted_at"], name: "index_rosters_on_submitted_at", using: :btree

  create_table "rosters_players", force: true do |t|
    t.integer "player_id",                        null: false
    t.integer "roster_id",                        null: false
    t.decimal "purchase_price",  default: 1000.0, null: false
    t.string  "player_stats_id"
    t.integer "market_id",                        null: false
  end

  add_index "rosters_players", ["market_id"], name: "index_rosters_players_on_market_id", using: :btree
  add_index "rosters_players", ["player_id", "roster_id"], name: "contest_rosters_players_index", unique: true, using: :btree

  create_table "sports", force: true do |t|
    t.string   "name",       null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "sports", ["name"], name: "index_sports_on_name", unique: true, using: :btree

  create_table "stat_events", force: true do |t|
    t.string   "activity",        null: false
    t.text     "data",            null: false
    t.decimal  "point_value",     null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "player_stats_id", null: false
    t.string   "game_stats_id",   null: false
  end

  add_index "stat_events", ["game_stats_id"], name: "index_stat_events_on_game_stats_id", using: :btree
  add_index "stat_events", ["player_stats_id", "game_stats_id", "activity"], name: "player_game_activity", unique: true, using: :btree

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

  create_table "transaction_records", force: true do |t|
    t.string   "event",                                   null: false
    t.integer  "user_id"
    t.integer  "roster_id"
    t.integer  "amount"
    t.integer  "contest_id"
    t.boolean  "is_tokens",               default: false
    t.string   "ios_transaction_id"
    t.text     "transaction_data"
    t.integer  "invitation_id"
    t.integer  "referred_id"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer  "reverted_transaction_id"
    t.integer  "promo_id"
  end

  add_index "transaction_records", ["roster_id"], name: "index_transaction_records_on_roster_id", using: :btree
  add_index "transaction_records", ["user_id"], name: "index_transaction_records_on_user_id", using: :btree

  create_table "users", force: true do |t|
    t.string   "name",                                   null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "email",                  default: "",    null: false
    t.string   "encrypted_password",     default: "",    null: false
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
    t.boolean  "admin",                  default: false
    t.string   "image_url"
    t.integer  "total_points",           default: 0,     null: false
    t.integer  "total_wins",             default: 0,     null: false
    t.decimal  "win_percentile",         default: 0.0,   null: false
    t.integer  "token_balance",          default: 0
    t.string   "avatar"
    t.string   "username"
    t.string   "fb_token"
    t.integer  "inviter_id"
    t.string   "avatar"
    t.text     "bonuses"
  end

  add_index "users", ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true, using: :btree
  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree
  add_index "users", ["username"], name: "index_users_on_username", unique: true, using: :btree

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
