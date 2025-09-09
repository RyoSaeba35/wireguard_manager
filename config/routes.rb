Rails.application.routes.draw do
  namespace :admin do
    get "dashboard/index"
  end
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    confirmations: 'users/confirmations'
  }

  namespace :admin do
    get 'dashboard', to: 'dashboard#index'
    resources :users, only: [:index, :show]
    resources :subscriptions, only: [:index, :show]
    resources :wireguard_clients, only: [:index, :show]
    resources :plans, only: [:create, :update]
    resource :setting, only: [:edit, :update], controller: 'setting'
    resources :servers, only: [:index, :new, :create, :edit, :update]
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Defines the root path route ("/")
  # root "posts#index"
  resources :users do
    resources :subscriptions, only: [:new, :create, :show]
  end

  root "home#index"

  get 'dashboard', to: 'dashboard#show', as: 'dashboard'
  get 'profile', to: 'users#profile', as: 'profile'
  patch 'update_profile', to: 'users#update_profile', as: 'update_profile'

  get 'privacy', to: 'pages#privacy'
  get 'terms', to: 'pages#terms'
  get 'logging', to: 'pages#logging'

  get 'expired_subscriptions', to: 'pages#subscriptions_expired', as: :expired_subscriptions

  get 'setup', to: 'dashboard#setup', as: :setup_guide

  get 'download_config/:filename', to: 'downloads#config', as: :download_config
  get 'download_qr_code/:filename', to: 'downloads#qr_code', as: :download_qr_code
end
