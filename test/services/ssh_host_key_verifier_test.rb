require "test_helper"

class SshHostKeyVerifierTest < ActiveSupport::TestCase
  FakeKey = Struct.new(:ssh_type)

  def handshake(blob, type: "ssh-ed25519")
    { key: FakeKey.new(type), key_blob: blob, fingerprint: "ignored", session: nil }
  end

  setup do
    @server = create_server(ssh_host_key_fingerprint: nil)
  end

  test "pins the host key on first connection" do
    assert SshHostKeyVerifier.new(@server).verify(handshake("key-A"))

    fingerprint = @server.reload.ssh_host_key_fingerprint
    assert_match(/\Assh-ed25519 SHA256:[A-Za-z0-9+\/]+\z/, fingerprint)
  end

  test "accepts the same key on later connections" do
    SshHostKeyVerifier.new(@server).verify(handshake("key-A"))

    assert SshHostKeyVerifier.new(@server.reload).verify(handshake("key-A"))
  end

  test "refuses a different key and keeps the pinned one" do
    SshHostKeyVerifier.new(@server).verify(handshake("key-A"))
    pinned = @server.reload.ssh_host_key_fingerprint

    assert_not SshHostKeyVerifier.new(@server).verify(handshake("key-B"))
    assert_equal pinned, @server.reload.ssh_host_key_fingerprint
  end

  test "refuses a different key type even with the same bytes" do
    SshHostKeyVerifier.new(@server).verify(handshake("key-A", type: "ssh-ed25519"))

    assert_not SshHostKeyVerifier.new(@server.reload).verify(handshake("key-A", type: "ssh-rsa"))
  end

  test "matches the format of ssh-keygen -l (unpadded base64 SHA256)" do
    expected = "ssh-ed25519 SHA256:" + Base64.strict_encode64(Digest::SHA256.digest("key-A")).delete("=")
    assert_equal expected, SshHostKeyVerifier.fingerprint_for(handshake("key-A"))
  end

  test "verify_signature passes the block result through" do
    verifier = SshHostKeyVerifier.new(@server)
    assert_equal true, verifier.verify_signature { true }
    assert_equal false, verifier.verify_signature { false }
  end
end
