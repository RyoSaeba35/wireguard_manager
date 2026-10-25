# app/services/ssh_host_key_verifier.rb
#
# 🔐 Verifies the VPN server's SSH host key (replaces verify_host_key: :never).
#
# Without this, anyone able to intercept the connection between Heroku and the
# OVH server could pose as the server: the app would hand over the SSH session
# and every key, password and peer it writes.
#
# Trust on first use: the first successful connection stores the host key's
# fingerprint in servers.ssh_host_key_fingerprint ("ssh-ed25519 SHA256:...").
# Every later connection must present exactly that key, otherwise it is refused.
#
# To check the stored value against the server:
#   ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub     (on the server)
# If you rebuild or reinstall the server (new host key), reset it once:
#   Server.find(ID).update!(ssh_host_key_fingerprint: nil)
#
# Usage:
#   Net::SSH.start(server.ip_address, server.ssh_user, ...,
#                  verify_host_key: SshHostKeyVerifier.new(server))
require "digest"
require "base64"

class SshHostKeyVerifier
  class Mismatch < StandardError; end

  def initialize(server)
    @server = server
  end

  # Called by Net::SSH during the handshake. Returning false aborts the
  # connection with Net::SSH::HostKeyMismatch / "host key verification failed".
  def verify(arguments)
    presented = self.class.fingerprint_for(arguments)
    return false if presented.nil?

    stored = @server.ssh_host_key_fingerprint.presence

    if stored.nil?
      pin!(presented)
      true
    elsif ActiveSupport::SecurityUtils.secure_compare(stored, presented)
      true
    else
      Rails.logger.error "🚨 SSH HOST KEY MISMATCH for server #{@server.name} (#{@server.ip_address}): " \
                         "expected #{stored}, got #{presented}. Connection refused. " \
                         "If the server was rebuilt, reset servers.ssh_host_key_fingerprint."
      false
    end
  end

  # Net::SSH calls this around the host key signature check
  def verify_signature
    yield
  end

  # "ssh-ed25519 SHA256:abc..." (same SHA256 format as ssh-keygen -l)
  def self.fingerprint_for(arguments)
    key = arguments[:key]
    blob = arguments[:key_blob]
    blob ||= Net::SSH::Buffer.from(:key, key).to_s if key
    return nil if blob.nil? || blob.empty?

    type = key.respond_to?(:ssh_type) ? key.ssh_type : "unknown"
    digest = Base64.strict_encode64(Digest::SHA256.digest(blob)).delete("=")
    "#{type} SHA256:#{digest}"
  end

  private

  def pin!(fingerprint)
    # update_column: no validations or callbacks, and safe inside the handshake
    @server.update_column(:ssh_host_key_fingerprint, fingerprint) if @server.persisted?
    @server.ssh_host_key_fingerprint = fingerprint
    Rails.logger.warn "🔑 Pinned SSH host key for server #{@server.name} (#{@server.ip_address}): #{fingerprint}"
  end
end
