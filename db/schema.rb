# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_04_17_082102) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

# Could not dump table "devices" because of following StandardError
#   Unknown type 'inet' for column 'last_connection_ip'


  create_table "jwt_denylists", force: :cascade do |t|
    t.string "jti"
    t.datetime "exp"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_jwt_denylists_on_jti"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "price", precision: 8, scale: 2, null: false
    t.string "interval", null: false
    t.boolean "active", default: true
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stripe_price_id"
    t.integer "position"
  end

  create_table "refresh_tokens", force: :cascade do |t|
    t.string "jti", null: false
    t.integer "user_id", null: false
    t.datetime "exp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exp"], name: "index_refresh_tokens_on_exp"
    t.index ["jti"], name: "index_refresh_tokens_on_jti", unique: true
    t.index ["user_id"], name: "index_refresh_tokens_on_user_id"
  end

  create_table "servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "ip_address", null: false
    t.string "wireguard_server_ip", null: false
    t.string "wireguard_public_key"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ssh_user"
    t.string "ssh_password"
    t.text "ssh_public_key"
    t.text "ssh_private_key"
    t.boolean "singbox_active", default: false
    t.string "singbox_server_name"
    t.string "singbox_salamander_password"
    t.string "singbox_ss_master_password"
    t.integer "singbox_ss_port", default: 443
    t.integer "singbox_hysteria2_port", default: 8443
    t.integer "wireguard_port", default: 53050
    t.string "clash_api_secret"
    t.integer "max_concurrent_connections", default: 225
    t.integer "config_pool_size", default: 3000
    t.string "location"
    t.string "city"
    t.string "country_code"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.boolean "healthy", default: true
    t.datetime "last_health_check"
    t.integer "health_failures", default: 0
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "user_id"
    t.string "status", default: "active"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", null: false
    t.decimal "price", precision: 8, scale: 2, null: false
    t.integer "plan_id"
    t.string "plan_interval"
    t.string "stripe_session_id"
    t.integer "max_devices", default: 3
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_session_id"], name: "index_subscriptions_on_stripe_session_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false
    t.datetime "locked_at"
    t.datetime "confirmed_at"
    t.string "confirmation_token"
    t.datetime "confirmation_sent_at"
    t.integer "sign_in_count"
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "failed_attempts"
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "vpn_config_sets", force: :cascade do |t|
    t.integer "server_id", null: false
    t.string "ip_address", null: false
    t.text "wireguard_private_key"
    t.text "wireguard_public_key"
    t.text "wireguard_preshared_key"
    t.string "hysteria2_password"
    t.string "shadowsocks_password"
    t.string "status", default: "available", null: false
    t.integer "device_id"
    t.datetime "last_rotated_at"
    t.datetime "last_used_at"
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_vpn_config_sets_on_device_id"
    t.index ["ip_address"], name: "index_vpn_config_sets_on_ip_address", unique: true
    t.index ["server_id", "status"], name: "index_vpn_config_sets_on_server_id_and_status"
    t.index ["server_id"], name: "index_vpn_config_sets_on_server_id"
    t.index ["status", "updated_at"], name: "index_vpn_config_sets_on_status_and_updated_at"
  end

  create_table "vpn_connections", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "device_id", null: false
    t.integer "config_set_id", null: false
    t.integer "server_id", null: false
    t.datetime "connected_at", null: false
    t.datetime "disconnected_at"
    t.bigint "bytes_sent"
    t.bigint "bytes_received"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["config_set_id"], name: "index_vpn_connections_on_config_set_id"
    t.index ["connected_at"], name: "index_vpn_connections_on_connected_at"
    t.index ["device_id", "connected_at"], name: "index_vpn_connections_on_device_id_and_connected_at"
    t.index ["device_id"], name: "index_vpn_connections_on_device_id"
    t.index ["server_id"], name: "index_vpn_connections_on_server_id"
    t.index ["user_id", "connected_at"], name: "index_vpn_connections_on_user_id_and_connected_at"
    t.index ["user_id"], name: "index_vpn_connections_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "devices", "subscriptions"
  add_foreign_key "devices", "users"
  add_foreign_key "refresh_tokens", "users"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "vpn_config_sets", "devices"
  add_foreign_key "vpn_config_sets", "servers"
  add_foreign_key "vpn_connections", "devices"
  add_foreign_key "vpn_connections", "servers"
  add_foreign_key "vpn_connections", "users"
  add_foreign_key "vpn_connections", "vpn_config_sets", column: "config_set_id"
end
