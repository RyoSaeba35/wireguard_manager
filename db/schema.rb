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

ActiveRecord::Schema[7.2].define(version: 2026_03_21_083641) do
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

  create_table "devices", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "subscription_id", null: false
    t.string "device_id", null: false
    t.string "platform", null: false
    t.string "name"
    t.boolean "active", default: false, null: false
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key"
    t.datetime "connected_at"
    t.datetime "last_heartbeat_at"
    t.index ["api_key"], name: "index_devices_on_api_key", unique: true
    t.index ["subscription_id"], name: "index_devices_on_subscription_id"
    t.index ["user_id", "device_id"], name: "index_devices_on_user_id_and_device_id", unique: true
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "hysteria2_clients", force: :cascade do |t|
    t.integer "subscription_id", null: false
    t.integer "device_id"
    t.string "name", null: false
    t.string "password", null: false
    t.string "status", default: "preallocated"
    t.datetime "expires_at"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_hysteria2_clients_on_device_id"
    t.index ["name"], name: "index_hysteria2_clients_on_name", unique: true
    t.index ["status"], name: "index_hysteria2_clients_on_status"
    t.index ["subscription_id"], name: "index_hysteria2_clients_on_subscription_id"
  end

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

  create_table "servers", force: :cascade do |t|
    t.string "name", null: false
    t.string "ip_address", null: false
    t.string "wireguard_server_ip", null: false
    t.string "wireguard_public_key"
    t.integer "max_subscriptions", default: 0
    t.integer "current_subscriptions", default: 0
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
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "shadowsocks_clients", force: :cascade do |t|
    t.integer "subscription_id", null: false
    t.integer "device_id"
    t.string "name", null: false
    t.string "password", null: false
    t.string "status", default: "preallocated"
    t.datetime "expires_at"
    t.datetime "connected_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["device_id"], name: "index_shadowsocks_clients_on_device_id"
    t.index ["name"], name: "index_shadowsocks_clients_on_name", unique: true
    t.index ["status"], name: "index_shadowsocks_clients_on_status"
    t.index ["subscription_id"], name: "index_shadowsocks_clients_on_subscription_id"
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
    t.integer "server_id"
    t.string "stripe_session_id"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["server_id"], name: "index_subscriptions_on_server_id"
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

  create_table "wireguard_clients", force: :cascade do |t|
    t.string "name"
    t.text "public_key"
    t.text "private_key"
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "expires_at"
    t.string "status", default: "active"
    t.integer "subscription_id", null: false
    t.integer "device_id"
    t.index ["device_id"], name: "index_wireguard_clients_on_device_id"
    t.index ["subscription_id"], name: "index_wireguard_clients_on_subscription_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "devices", "subscriptions"
  add_foreign_key "devices", "users"
  add_foreign_key "hysteria2_clients", "devices"
  add_foreign_key "hysteria2_clients", "subscriptions"
  add_foreign_key "shadowsocks_clients", "devices"
  add_foreign_key "shadowsocks_clients", "subscriptions"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "subscriptions", "servers"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "wireguard_clients", "devices"
  add_foreign_key "wireguard_clients", "subscriptions"
end
