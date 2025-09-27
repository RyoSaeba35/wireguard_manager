def perform(*args)
  # Parse DATABASE_URL for connection details
  db_url = URI.parse(ENV['DATABASE_URL'])
  db_host = db_url.host
  db_port = db_url.port
  db_user = db_url.user
  db_password = db_url.password
  db_name = db_url.path.gsub('/', '')

  # Define the backup filename with a timestamp
  backup_file = "railway_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
  local_path = "/tmp/#{backup_file}"

  # Dump the database to a temporary file in plain SQL format
  `PGPASSWORD="#{db_password}" pg_dump -F p -h #{db_host} -p #{db_port} -U #{db_user} -d #{db_name} -f #{local_path}`

  # Check if the backup file was created and is not empty
  unless File.exist?(local_path) && File.size(local_path) > 0
    raise "Backup failed: #{local_path} is empty or does not exist"
  end

  # Upload to Wasabi using the AWS SDK
  s3 = Aws::S3::Resource.new(
    region: ENV['AWS_REGION'],
    endpoint: ENV['AWS_ENDPOINT'],
    access_key_id: ENV['AWS_ACCESS_KEY_ID'],
    secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
    force_path_style: true
  )
  transfer_manager = Aws::S3::TransferManager.new(client: s3.client)
  transfer_manager.upload_file(
    local_path,
    bucket: ENV['AWS_BUCKET'],
    key: backup_file
  )

  # Remove the temporary file
  File.delete(local_path)
end
