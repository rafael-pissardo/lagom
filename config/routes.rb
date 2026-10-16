Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :merchants, only: %i[index show] do
    resources :orders, only: :index
  end
  resources :disbursements, only: %i[index show]
  resources :monthly_fees, only: :index
  resources :csv_imports, only: %i[index new create show]
  get "reports/yearly", to: "reports#yearly"

  mount MissionControl::Jobs::Engine, at: "/jobs"

  get "up" => "rails/health#show", as: :rails_health_check

  root "merchants#index"
end
