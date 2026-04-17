# app/services/server_selector_service.rb
class ServerSelectorService
  # Find best server based on location and load
  def find_best_server(user_ip: nil, preferred_location: nil)
    candidates = Server.active.healthy

    return nil if candidates.empty?

    # Filter by location if specified
    if preferred_location.present?
      location_filtered = candidates.where(
        "location LIKE ? OR city LIKE ? OR country_code = ?",
        "%#{preferred_location}%",
        "%#{preferred_location}%",
        preferred_location.upcase
      )
      candidates = location_filtered if location_filtered.any?
    end

    # Score each server (distance + load)
    scored = candidates.map do |server|
      distance_score = user_ip ? calculate_distance_score(user_ip, server) : 0
      load_score = calculate_load_score(server)

      # Combined score (50% distance, 50% load)
      total_score = (distance_score * 0.5) + (load_score * 0.5)

      { server: server, score: total_score }
    end

    # Return server with lowest score (best)
    scored.min_by { |s| s[:score] }&.dig(:server)
  end

  # Find closest server by geographic distance
  def find_closest_server(user_ip)
    servers = Server.active.healthy.where.not(latitude: nil, longitude: nil)

    return servers.first if servers.count == 1
    return nil if servers.empty?

    user_location = get_user_location(user_ip)
    return servers.first unless user_location

    # Calculate distances
    distances = servers.map do |server|
      distance = haversine_distance(
        user_location[:latitude],
        user_location[:longitude],
        server.latitude,
        server.longitude
      )
      { server: server, distance: distance }
    end

    # Return closest
    distances.min_by { |d| d[:distance] }&.dig(:server)
  end

  # Find least loaded server
  def find_least_loaded_server
    servers = Server.active.healthy
    return nil if servers.empty?

    servers.min_by(&:load_percent)
  end

  private

  # ==========================================
  # SCORING ALGORITHMS
  # ==========================================

  def calculate_distance_score(user_ip, server)
    return 50 unless server.latitude && server.longitude

    user_location = get_user_location(user_ip)
    return 50 unless user_location

    distance = haversine_distance(
      user_location[:latitude],
      user_location[:longitude],
      server.latitude,
      server.longitude
    )

    # Normalize: 0km = score 0, 20000km = score 100
    [distance / 200.0, 100].min
  end

  def calculate_load_score(server)
    # Load percentage as score (0% = 0, 100% = 100)
    server.load_percent
  end

  # ==========================================
  # GEOLOCATION
  # ==========================================

  def get_user_location(ip)
    return nil if ip.blank?

    Rails.cache.fetch("location_#{ip}", expires_in: 1.hour) do
      response = Net::HTTP.get(URI("http://ip-api.com/json/#{ip}"))
      data = JSON.parse(response)

      if data['status'] == 'success'
        {
          latitude: data['lat'],
          longitude: data['lon'],
          country: data['country'],
          city: data['city']
        }
      else
        nil
      end
    rescue StandardError => e
      Rails.logger.error("Failed to get location for #{ip}: #{e.message}")
      nil
    end
  end

  # ==========================================
  # HAVERSINE DISTANCE (km)
  # ==========================================

  def haversine_distance(lat1, lon1, lat2, lon2)
    # Earth radius in kilometers
    radius = 6371

    # Convert to radians
    lat1_rad = lat1 * Math::PI / 180
    lat2_rad = lat2 * Math::PI / 180
    delta_lat = (lat2 - lat1) * Math::PI / 180
    delta_lon = (lon2 - lon1) * Math::PI / 180

    # Haversine formula
    a = Math.sin(delta_lat / 2)**2 +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) *
        Math.sin(delta_lon / 2)**2

    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    radius * c
  end
end
