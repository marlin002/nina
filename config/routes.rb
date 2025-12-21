Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Top-level HTML search (simple query via ?q=...)
  get "search", to: "search#index", as: :search

  # API routes
  namespace :api do
    namespace :v1 do
      # GET /api/v1/regulations
      get "regulations", to: "regulations#index"

      # GET /api/v1/regulations/:year/:number/structure
      get "regulations/:year/:number/structure", to: "regulations#structure"

      # GET /api/v1/regulations/:year/:number/sections/:section (no chapter)
      get "regulations/:year/:number/sections/:section", to: "regulations#section_without_chapter"

      # GET /api/v1/regulations/:year/:number/chapters/:chapter/sections/:section
      get "regulations/:year/:number/chapters/:chapter/sections/:section", to: "regulations#section_with_chapter"

      # GET /api/v1/regulations/:year/:number/appendices/:appendix
      get "regulations/:year/:number/appendices/:appendix", to: "regulations#appendix"

      # GET /api/v1/search?q=arbetsgivaren
      get "search", to: "search#index", defaults: { format: :json }

      # catch-all
      match "*unmatched", to: "regulations#not_found", via: :all
    end
  end

  # Scrapes routes
  resources :scrapes, only: [ :index ] do
    collection do
      get :search
      get :all
      get :about
      get :api_info
      get :dev_reference_lookup
    end
    member do
      get :raw
    end
  end

  # Defines the root path route ("/")
  root "scrapes#index"
end
