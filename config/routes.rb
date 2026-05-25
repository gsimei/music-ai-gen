Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users

  constraints BrandConstraint.new(:b2b) do
    # B2B routes (JinglePro)
    get   "orders/new",          to: "orders#new",         as: :new_order
    get   "orders/wizard/:step", to: "orders#wizard_show", as: :wizard_order,  constraints: { step: /[1-5]/ }
    patch "orders/wizard/:step", to: "orders#wizard_update",                   constraints: { step: /[1-5]/ }
    resources :orders, only: [ :show ]
  end

  constraints BrandConstraint.new(:b2c) do
    # B2C routes (MusicaRegalo)
    get   "orders/new",          to: "orders#new"
    get   "orders/wizard/:step", to: "orders#wizard_show", constraints: { step: /[1-5]/ }
    patch "orders/wizard/:step", to: "orders#wizard_update", constraints: { step: /[1-5]/ }
    resources :orders, only: [ :show ]
  end
end
