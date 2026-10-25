require "test_helper"

# The SSH part (rotate_and_update_peers) is replaced by a stub: these tests
# cover which configs get recycled, not the server commands.
class VpnConfigSetServiceTest < ActiveSupport::TestCase
  setup do
    @server = create_server
    @service = VpnConfigSetService.new(@server)
  end

  test "recycles only configs released more than 5 minutes ago" do
    stale  = create_config_set(server: @server, status: "used", last_used_at: 10.minutes.ago)
    recent = create_config_set(server: @server, status: "used", last_used_at: 1.minute.ago)
    in_use = create_config_set(server: @server, status: "in_use", last_used_at: 1.hour.ago)

    rotated_ids = nil
    @service.stub(:rotate_and_update_peers, ->(configs) { rotated_ids = configs.map(&:id) }) do
      assert_equal 1, @service.recycle_stale_configs
    end

    assert_equal [stale.id], rotated_ids
    assert_equal "available", stale.reload.status
    assert_equal "used", recent.reload.status
    assert_equal "in_use", in_use.reload.status
  end

  test "a config released DURING the SSH step is not marked available without rotation" do
    stale = create_config_set(server: @server, status: "used", last_used_at: 10.minutes.ago)
    late  = create_config_set(server: @server, status: "in_use", last_used_at: 1.hour.ago)

    slow_ssh = lambda do |configs|
      # While the job is busy on the server, a device disconnects and its
      # config becomes 'used' with an old timestamp. The old code's second
      # query picked it up and flipped it to 'available' with its old keys.
      late.update!(status: "used", device: nil, last_used_at: 10.minutes.ago)
      assert_equal [stale.id], configs.map(&:id)
    end

    @service.stub(:rotate_and_update_peers, slow_ssh) do
      assert_equal 1, @service.recycle_stale_configs
    end

    assert_equal "available", stale.reload.status
    assert_equal "used", late.reload.status, "late config must wait for the next run (and a rotation)"
  end

  test "nothing goes back to the pool if rotation fails" do
    stale = create_config_set(server: @server, status: "used", last_used_at: 10.minutes.ago)

    @service.stub(:rotate_and_update_peers, ->(_configs) { raise "SSH timeout" }) do
      assert_raises(RuntimeError) { @service.recycle_stale_configs }
    end

    assert_equal "used", stale.reload.status
  end

  test "returns 0 and skips SSH when nothing is stale" do
    create_config_set(server: @server, status: "available")

    called = false
    @service.stub(:rotate_and_update_peers, ->(_configs) { called = true }) do
      assert_equal 0, @service.recycle_stale_configs
    end
    assert_not called
  end
end
