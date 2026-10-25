require "test_helper"

class VpnConfigSetTest < ActiveSupport::TestCase
  setup do
    @paris = create_server(name: "Paris")
    @frankfurt = create_server(name: "Frankfurt")
  end

  test "two servers can use the same tunnel address" do
    create_config_set(server: @paris, ip_address: "10.155.0.2")
    config = create_config_set(server: @frankfurt, ip_address: "10.155.0.2")

    assert config.persisted?
  end

  test "the same server cannot use an address twice (validation)" do
    create_config_set(server: @paris, ip_address: "10.155.0.2")
    duplicate = VpnConfigSet.new(server: @paris, ip_address: "10.155.0.2", status: "available")

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:ip_address, :taken)
  end

  test "the same server cannot use an address twice (database index)" do
    create_config_set(server: @paris, ip_address: "10.155.0.2")

    assert_raises(ActiveRecord::RecordNotUnique) do
      VpnConfigSet.insert_all!([{ server_id: @paris.id, ip_address: "10.155.0.2", status: "available",
                                 created_at: Time.current, updated_at: Time.current }])
    end
  end

  test "claim!, release! and recycle! move a config through the pool" do
    config = create_config_set(server: @paris)
    device = create_device(user: create_user)

    config.claim!(device)
    assert_equal ["in_use", device.id], [config.status, config.device_id]

    config.release!
    assert_equal ["used", nil], [config.reload.status, config.device_id]

    config.recycle!
    assert_equal "available", config.reload.status
  end
end
