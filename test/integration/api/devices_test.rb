require "test_helper"

class Api::DevicesTest < ActionDispatch::IntegrationTest
  CLOUDFLARE_EDGE = "172.68.234.242"

  setup do
    use_api_host!
    @user = create_user
    @server = create_server
    @selector = Object.new
    server = @server
    @selector.define_singleton_method(:find_best_server) { |**_opts| server }
  end

  def register(user: @user, device_id: SecureRandom.uuid)
    post "/api/devices/register",
         params: { device_id: device_id, platform: "android", name: "Pixel" },
         headers: { "Authorization" => "Bearer #{access_token_for(user)}" },
         as: :json
  end

  def connect(device, from: "88.120.1.2")
    ServerSelectorService.stub(:new, @selector) do
      post "/api/connect/#{device.device_id}",
           headers: { "X-Api-Key" => device.api_key, "CF-Connecting-IP" => from },
           env: { "REMOTE_ADDR" => CLOUDFLARE_EDGE },
           as: :json
    end
  end

  # ---------- register ----------

  test "a user without any subscription can register a device" do
    register
    assert_response :created
    device = Device.find_by!(device_id: json["device_id"])
    assert_nil device.subscription
    assert_equal json["api_key"], device.api_key
  end

  test "re-registering on the same subscription keeps the API key" do
    create_subscription(user: @user)
    device_id = SecureRandom.uuid
    register(device_id: device_id)
    first_key = json["api_key"]

    register(device_id: device_id)
    assert_equal first_key, json["api_key"]
  end

  test "moving a device to another user rotates its API key" do
    device_id = SecureRandom.uuid
    create_subscription(user: @user)
    register(device_id: device_id)
    old_key = json["api_key"]

    other = create_user
    create_subscription(user: other)
    register(user: other, device_id: device_id)

    assert_response :created
    assert_not_equal old_key, json["api_key"]
    assert_equal other, Device.find_by!(device_id: device_id).user

    # The previous owner's key no longer works
    post "/api/heartbeat/#{device_id}", headers: { "X-Api-Key" => old_key }, as: :json
    assert_response :unauthorized
  end

  test "register needs a valid JWT" do
    post "/api/devices/register", params: { device_id: "x", platform: "android" }, as: :json
    assert_response :unauthorized
  end

  # ---------- connect / disconnect ----------

  test "connect without a subscription asks the user to subscribe" do
    device = create_device(user: @user, subscription: nil)
    connect(device)
    assert_response :forbidden
    assert_equal "subscribe", json["action_required"]
  end

  test "connect with an expired subscription asks the user to renew" do
    subscription = create_subscription(user: @user)
    subscription.update_column(:expires_at, 1.day.ago)
    device = create_device(user: @user, subscription: subscription)

    connect(device)
    assert_response :forbidden
    assert_equal "renew", json["action_required"]
  end

  test "connect claims a config from the pool and returns WireGuard credentials" do
    config = create_config_set(server: @server)
    device = create_device(user: @user, subscription: create_subscription(user: @user))

    connect(device)
    assert_response :ok
    assert_equal config.wireguard_private_key, json.dig("credentials", "wireguard", "client_private_key")
    assert_equal "in_use", config.reload.status
    assert_equal device.id, config.device_id
    assert device.reload.active
  end

  test "connect records the visitor's real IP behind Cloudflare, not the edge address" do
    create_config_set(server: @server)
    device = create_device(user: @user, subscription: create_subscription(user: @user))

    connect(device, from: "88.120.1.2")
    assert_response :ok
    assert_equal "88.120.1.2", device.reload.last_connection_ip.to_s
  end

  test "connect returns 503 when the pool is empty" do
    device = create_device(user: @user, subscription: create_subscription(user: @user))
    connect(device)
    assert_response :service_unavailable
  end

  test "connect enforces the device limit" do
    subscription = create_subscription(user: @user) # max_devices: 3
    3.times { create_device(user: @user, subscription: subscription, active: true) }
    create_config_set(server: @server)
    fourth = create_device(user: @user, subscription: subscription)

    connect(fourth)
    assert_response :too_many_requests
  end

  test "disconnect puts the config back as 'used' (waiting for rotation)" do
    config = create_config_set(server: @server)
    device = create_device(user: @user, subscription: create_subscription(user: @user))
    connect(device)

    post "/api/disconnect/#{device.device_id}", headers: { "X-Api-Key" => device.api_key }, as: :json
    assert_response :ok
    assert_equal "used", config.reload.status
    assert_nil config.device_id
    assert_not device.reload.active
  end

  # ---------- status ----------

  test "status works for a device holding a config without an open connection" do
    subscription = create_subscription(user: @user)
    device = create_device(user: @user, subscription: subscription)
    create_config_set(server: @server, status: "in_use", device: device)

    get "/api/status", headers: { "X-Api-Key" => device.api_key }
    assert_response :ok
    assert_nil json["connection"]
  end

  test "status refuses a device without a subscription" do
    device = create_device(user: @user, subscription: nil)
    get "/api/status", headers: { "X-Api-Key" => device.api_key }
    assert_response :forbidden
    assert_equal "subscribe", json["action_required"]
  end
end
