require "test_helper"

class Api::SessionsTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password123!"

  setup do
    use_api_host!
    @user = create_user(password: PASSWORD)
  end

  def login(password: PASSWORD, user: @user)
    post "/api/login", params: { email: user.email, password: password }, as: :json
  end

  def refresh(refresh_token)
    post "/api/refresh", params: { refresh_token: refresh_token }, as: :json
  end

  # ---------- login ----------

  test "login returns an access token and a refresh token" do
    login
    assert_response :ok
    assert json["access_token"].present?
    assert json["refresh_token"].present?
  end

  test "the refresh token is linked to the access token issued with it" do
    login
    access_jti = JWT.decode(json["access_token"], nil, false).first["jti"]
    assert @user.refresh_tokens.exists?(access_jti: access_jti)
  end

  test "unknown email and wrong password give the same 401" do
    post "/api/login", params: { email: "nobody@example.com", password: "x" }, as: :json
    assert_response :unauthorized
    unknown_error = json["error"]

    login(password: "wrong")
    assert_response :unauthorized
    assert_equal unknown_error, json["error"]
  end

  test "failed logins are counted and lock the account after 5" do
    4.times { login(password: "wrong") }
    assert_equal 4, @user.reload.failed_attempts
    assert_not @user.access_locked?

    login(password: "wrong")
    assert @user.reload.access_locked?

    # Even the right password is refused while locked
    login
    assert_response :forbidden
    assert_match(/locked/i, json["error"])
  end

  test "the account unlocks by itself after 1 hour" do
    5.times { login(password: "wrong") }
    assert @user.reload.access_locked?

    travel 61.minutes do
      login
      assert_response :ok
    end
  end

  test "a successful login resets the failed attempts counter" do
    3.times { login(password: "wrong") }
    login
    assert_response :ok
    assert_equal 0, @user.reload.failed_attempts
  end

  test "unconfirmed users cannot log in" do
    user = User.create!(email: "new-#{SecureRandom.hex(3)}@example.com", password: PASSWORD, password_confirmation: PASSWORD)
    login(user: user)
    assert_response :forbidden
  end

  # ---------- access vs refresh tokens ----------

  test "an access token works on the API" do
    create_subscription(user: @user)
    login
    get "/api/subscription", headers: { "Authorization" => "Bearer #{json['access_token']}" }
    assert_response :ok
  end

  test "a refresh token is rejected as an access token" do
    create_subscription(user: @user)
    login
    get "/api/subscription", headers: { "Authorization" => "Bearer #{json['refresh_token']}" }
    assert_response :unauthorized
    assert_equal "Invalid token type", json["error"]
  end

  test "an access token is rejected at /api/refresh" do
    login
    refresh(json["access_token"])
    assert_response :unauthorized
    assert_equal "Invalid token type", json["error"]
  end

  # ---------- refresh ----------

  test "refresh rotates the refresh token: the old one cannot be reused" do
    login
    first_refresh = json["refresh_token"]

    refresh(first_refresh)
    assert_response :ok
    assert json["refresh_token"].present?
    assert_not_equal first_refresh, json["refresh_token"]

    refresh(first_refresh)
    assert_response :unauthorized
  end

  test "refresh is refused while the account is locked, and works again after unlock" do
    login
    refresh_token = json["refresh_token"]

    @user.lock_access!(send_instructions: false)
    refresh(refresh_token)
    assert_response :forbidden

    @user.unlock_access!
    refresh(refresh_token)
    assert_response :ok
  end

  # ---------- logout ----------

  test "logout signs out this device only" do
    login
    phone = json.slice("access_token", "refresh_token")
    login
    laptop = json.slice("access_token", "refresh_token")

    delete "/api/logout", headers: { "Authorization" => "Bearer #{phone['access_token']}" }
    assert_response :ok

    refresh(phone["refresh_token"])
    assert_response :unauthorized, "the phone's session must be revoked"

    refresh(laptop["refresh_token"])
    assert_response :ok, "the laptop must stay signed in"
  end

  test "logout revokes the access token too" do
    create_subscription(user: @user)
    login
    access = json["access_token"]

    delete "/api/logout", headers: { "Authorization" => "Bearer #{access}" }
    get "/api/subscription", headers: { "Authorization" => "Bearer #{access}" }
    assert_response :unauthorized
  end

  test "logout still works with an expired access token" do
    login
    tokens = json.slice("access_token", "refresh_token")

    travel 45.minutes do
      delete "/api/logout", headers: { "Authorization" => "Bearer #{tokens['access_token']}" }
      assert_response :ok
      refresh(tokens["refresh_token"])
      assert_response :unauthorized
    end
  end

  test "logout also revokes legacy refresh tokens that have no access_jti" do
    legacy = @user.generate_refresh_token # issued before this change: no access_jti
    login

    delete "/api/logout", headers: { "Authorization" => "Bearer #{json['access_token']}" }

    refresh(legacy)
    assert_response :unauthorized
  end
end
