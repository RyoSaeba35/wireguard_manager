# app/services/ssh_key_manager.rb
module SshKeyManager
  def write_private_key(server)
    path = "/tmp/server_#{server.id}_private_key_#{SecureRandom.hex(8)}"
    File.write(path, server.ssh_private_key)
    File.chmod(0600, path)
    path
  end
end
