Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users

  # Stripe webhook — outside BrandConstraint (no brand/locale detection needed)
  post "stripe/webhook", to: "stripe#webhook", as: :stripe_webhook

  constraints BrandConstraint.new(:b2b) do
    # B2B routes (JinglePro)
    get   "orders/new",          to: "orders#new",         as: :new_order
    get   "orders/wizard/:step", to: "orders#wizard_show", as: :wizard_order,  constraints: { step: /[1-5]/ }
    patch "orders/wizard/:step", to: "orders#wizard_update",                   constraints: { step: /[1-5]/ }
    resources :orders, only: [ :show ] do
      post :checkout, on: :member
    end
    # Lyrics review routes — named routes defined once in b2b block to avoid duplicate helper name errors
    get  "orders/:id/lyrics",            to: "lyrics#show",       as: :order_lyrics
    post "orders/:id/approve_lyrics",    to: "lyrics#approve",    as: :approve_order_lyrics
    post "orders/:id/lyrics/regenerate", to: "lyrics#regenerate", as: :regenerate_order_lyrics
  end

  constraints BrandConstraint.new(:b2c) do
    # B2C routes (MusicaRegalo)
    get   "orders/new",          to: "orders#new"
    get   "orders/wizard/:step", to: "orders#wizard_show", constraints: { step: /[1-5]/ }
    patch "orders/wizard/:step", to: "orders#wizard_update", constraints: { step: /[1-5]/ }
    resources :orders, only: [ :show ] do
      post :checkout, on: :member
    end
    # Lyrics review routes — no named helpers (already defined in b2b block)
    get  "orders/:id/lyrics",            to: "lyrics#show"
    post "orders/:id/approve_lyrics",    to: "lyrics#approve"
    post "orders/:id/lyrics/regenerate", to: "lyrics#regenerate"
  end
end
