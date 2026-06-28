# app/services/ssh_key_manager.rb
module SshKeyManager
  # Block form: always cleans up the temp file, even on error.
  # Use this for all new callers:
  #
  #   SshKeyManager.with_private_key(server) do |path|
  #     Net::SSH.start(server.ip_address, server.ssh_user, keys: [path], ...)
  #   end
  #
  def self.with_private_key(server)
    path = write_key(server)
    yield path
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  # Legacy instance method kept for existing callers (e.g. VpnConfigSetService).
  # Callers are responsible for deleting the file in their own ensure block.
  # Prefer with_private_key for any new code.
  def write_private_key(server)
    self.class.write_key(server)
  end

  def self.write_key(server)
    path = "/tmp/server_#{server.id}_private_key_#{SecureRandom.hex(8)}"
    File.write(path, server.ssh_private_key)
    File.chmod(0600, path)
    path
  end
end
