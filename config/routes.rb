Rails.application.routes.draw do
  # Admin namespace: Group all admin routes under a scope for clarity and maintainability
  namespace :admin do
    # Dashboard: Use 'root' for the admin dashboard to avoid redundancy
    get 'dashboard', to: 'dashboard#index'

    # Admin resources: Group related resources and use 'only' to limit actions
    # Users: Add create, destroy, and nested subscriptions
    resources :users, only: [:index, :create] do
      member do
        delete '', to: 'users#destroy', as: ''
      end
      # Nested subscriptions for users
      resources :subscriptions, only: [:create] do
        post 'cancel', on: :member  # Custom action to cancel a subscription
      end
    end
    resources :subscriptions, only: [:index, :show]
    resources :wireguard_clients, only: [:index, :show]
    resources :plans, only: [:index, :create, :update]

    # Singleton resource for settings (since there's only one setting)
    resource :setting, only: [:edit, :update], controller: 'setting'

    # Servers: Custom action for SSH key generation
    resources :servers, only: [:index, :new, :create, :edit, :update] do
      collection do
        post :generate_ssh_key
      end
    end
  end

  # Devise: Custom controllers for registrations and confirmations
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    confirmations: 'users/confirmations'
  }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # User resources: Nested subscriptions
  resources :users do
    resources :subscriptions, only: [:new, :create, :show] do
      collection do
        post 'create_pending'
        post 'create_checkout_session'
      end
      member do
        patch :cancel
      end
    end
  end

  # Stripe webhook: Use 'post' and a clear path
  post '/stripe/webhook', to: 'stripe_webhooks#create'

  # Public routes: Group related routes and use 'as' for clarity
  root "home#index"
  get 'dashboard', to: 'dashboard#show', as: 'dashboard'
  get 'profile', to: 'users#profile', as: 'profile'
  patch 'update_profile', to: 'users#update_profile', as: 'update_profile'

  # Static pages: Group and use 'as' for clarity
  get 'privacy', to: 'pages#privacy'
  get 'terms', to: 'pages#terms'
  get 'logging', to: 'pages#logging'
  get 'expired_subscriptions', to: 'pages#subscriptions_expired', as: :expired_subscriptions

  # Setup guide and downloads: Group and use 'as' for clarity
  get 'setup', to: 'dashboard#setup', as: :setup_guide
  get 'download_config/:filename', to: 'downloads#config', as: :download_config
  get 'download_qr_code/:filename', to: 'downloads#qr_code', as: :download_qr_code

  get 'dashboard/fetch_server_status', to: 'dashboard#fetch_server_status'

  # API namespace for Flutter app
  constraints subdomain: 'api' do
    namespace :api do
      # Auth
      post   'login',   to: 'sessions#create'
      post   'refresh', to: 'sessions#refresh'
      delete 'logout',  to: 'sessions#destroy'

      # Device registration
      post 'devices/register', to: 'devices#register'

      # Session management (⭐ Added constraints to allow dots in device_id)
      post 'connect/:device_id',    to: 'devices#connect',    constraints: { device_id: /[^\/]+/ }
      post 'disconnect/:device_id', to: 'devices#disconnect', constraints: { device_id: /[^\/]+/ }
      post 'heartbeat/:device_id',  to: 'devices#heartbeat',  constraints: { device_id: /[^\/]+/ }

      # Credentials (⭐ Added constraint)
      get 'credentials/:device_id', to: 'devices#credentials', constraints: { device_id: /[^\/]+/ }

      # Subscription status
      get 'subscription', to: 'subscriptions#show'

      # User status
      get 'status', to: 'users#status'
    end
  end
end
