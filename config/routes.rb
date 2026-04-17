# config/routes.rb
Rails.application.routes.draw do
  # ==========================================
  # ADMIN NAMESPACE
  # ==========================================
  namespace :admin do
    # Dashboard
    get 'dashboard', to: 'dashboard#show', as: :dashboard
    root to: 'dashboard#show'

    # Users Management
    resources :users, only: [:index, :create, :show, :edit, :update] do
      member do
        delete '', to: 'users#destroy', as: ''
        patch :toggle_admin
      end

      resources :subscriptions, only: [:create, :show] do
        member do
          post :cancel
          post :renew
        end
      end
    end

    # Subscriptions Management
    resources :subscriptions, only: [:index, :show, :edit, :update] do
      member do
        post :cancel
        post :renew
        post :extend
      end
    end

    # ⭐ Servers Management (Pooling Architecture)
    resources :servers do
      member do
        patch :toggle_active
        post :rebuild_pool
        # Optional routes (remove if not using):
        # get :metrics
        # post :health_check
      end

      collection do
        post :generate_ssh_key
      end
    end

    # Plans Management
    resources :plans, only: [:index, :create, :update, :destroy] do
      member do
        patch :toggle_active
      end
    end

    # WireGuard Clients (Legacy - may remove after migration)
    resources :wireguard_clients, only: [:index, :show, :destroy]

    # ⭐ System Setting (Singular - only ONE settings record)
    resource :setting, only: [:edit, :update], controller: 'setting'

    # ⭐ Optional: Connections monitoring (add if you create the controller)
    # resources :connections, only: [:index, :show] do
    #   member do
    #     delete :disconnect
    #   end
    # end
  end

  # ==========================================
  # DEVISE AUTHENTICATION
  # ==========================================
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    confirmations: 'users/confirmations'
  }

  # ==========================================
  # HEALTH CHECK
  # ==========================================
  get "up" => "rails/health#show", as: :rails_health_check

  # ==========================================
  # PWA
  # ==========================================
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # ==========================================
  # USER SUBSCRIPTIONS
  # ==========================================
  resources :users do
    resources :subscriptions, only: [:new, :create, :show] do
      collection do
        post 'create_pending'
        post 'create_checkout_session'
      end

      member do
        patch :cancel
        post :renew
      end
    end
  end

  # ==========================================
  # STRIPE WEBHOOKS
  # ==========================================
  post '/stripe/webhook', to: 'stripe_webhooks#create'

  # ==========================================
  # PUBLIC PAGES
  # ==========================================
  root "home#index"

  get 'dashboard', to: 'dashboard#show', as: 'dashboard'
  get 'profile', to: 'users#profile', as: 'profile'
  patch 'update_profile', to: 'users#update_profile', as: 'update_profile'

  # Static pages
  get 'privacy', to: 'pages#privacy'
  get 'terms', to: 'pages#terms'
  get 'logging', to: 'pages#logging'
  get 'expired_subscriptions', to: 'pages#subscriptions_expired', as: :expired_subscriptions

  # Setup guide and downloads
  get 'setup', to: 'dashboard#setup', as: :setup_guide
  get 'download_config/:filename', to: 'downloads#config', as: :download_config, constraints: { filename: /[^\/]+/ }
  get 'download_qr_code/:filename', to: 'downloads#qr_code', as: :download_qr_code, constraints: { filename: /[^\/]+/ }

  # Server status
  get 'dashboard/fetch_server_status', to: 'dashboard#fetch_server_status'

  # ==========================================
  # API NAMESPACE (Flutter App)
  # ==========================================
  constraints subdomain: 'api' do
    namespace :api do
      # Authentication
      post   'login',   to: 'sessions#create'
      post   'refresh', to: 'sessions#refresh'
      delete 'logout',  to: 'sessions#destroy'

      # Device Management
      post 'devices/register', to: 'devices#register'

      # ⭐ VPN Session Management (Pooling)
      post 'connect/:device_id',    to: 'devices#connect',    constraints: { device_id: /[^\/]+/ }
      post 'disconnect/:device_id', to: 'devices#disconnect', constraints: { device_id: /[^\/]+/ }
      post 'heartbeat/:device_id',  to: 'devices#heartbeat',  constraints: { device_id: /[^\/]+/ }

      # ⭐ Credentials (Returns fresh config from pool)
      get 'credentials/:device_id', to: 'devices#credentials', constraints: { device_id: /[^\/]+/ }

      # Subscription Management
      get 'subscription', to: 'subscriptions#show'
      get 'subscription/:device_id', to: 'subscriptions#show_by_device', constraints: { device_id: /[^\/]+/ }

      # User Status
      get 'status', to: 'users#status'
    end
  end
end
