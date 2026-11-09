Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  mount ActionCable.server => "/cable"

  devise_for :users,
             controllers: {
               sessions:      "users/sessions",
               registrations: "users/registrations"
             }

  # Stripe webhook
  post "stripe/webhook", to: "stripe#webhook", as: :stripe_webhook

  root "pages#home"
  resources :campaigns, only: %i[new create show edit update] do
    get :status, on: :member
    post :render_video, on: :member
    post :retry_generation, on: :member
    get :download, on: :member
    post :test_payment, on: :member if Rails.env.development?
    post :save_music_profile, on: :member
  end
  get   "orders/new",          to: "orders#new",         as: :new_order
  get   "orders/wizard/:step", to: "orders#wizard_show", as: :wizard_order,  constraints: { step: /[1-5]/ }
  patch "orders/wizard/:step", to: "orders#wizard_update",                   constraints: { step: /[1-5]/ }
  resources :orders, only: [ :show ] do
    post :checkout,          on: :member
    post :approve_lyrics,    on: :member, path: "spf/approve_lyrics"
    post :regenerate_lyrics, on: :member, path: "spf/regenerate_lyrics"
    post :approve_music,     on: :member, path: "spf/approve_music"
    post :regenerate_music,  on: :member, path: "spf/regenerate_music"

    resource :soundtrack_input, only: %i[new create], path: "soundtrack"
  end
  get  "orders/:id/lyrics",            to: "lyrics#show",       as: :order_lyrics
  post "orders/:id/approve_lyrics",    to: "lyrics#approve",    as: :approve_order_lyrics
  post "orders/:id/lyrics/regenerate", to: "lyrics#regenerate", as: :regenerate_order_lyrics
  get  "orders/:id/preview",           to: "music_preview#show",    as: :order_music_preview
  post "orders/:id/approve_music",     to: "music_preview#approve", as: :approve_order_music

  # Chat interface
  get  "orders/:order_id/chat",                   to: "order_chat#show",              as: :order_chat
  get  "orders/:order_id/chat/status",            to: "order_chat#status",            as: :order_chat_status
  post "orders/:order_id/chat",                   to: "order_chat#create",            as: :order_chat_message
  post "orders/:order_id/chat/generate_music",    to: "order_chat#generate_music",    as: :order_chat_generate_music
  post "orders/:order_id/chat/approve_lyrics",    to: "order_chat#approve_lyrics",    as: :order_chat_approve_lyrics
  post "orders/:order_id/chat/regenerate_lyrics", to: "order_chat#regenerate_lyrics", as: :order_chat_regenerate_lyrics
  post "orders/:order_id/chat/approve_music",     to: "order_chat#approve_music",     as: :order_chat_approve_music
  post "orders/:order_id/chat/regenerate_music",  to: "order_chat#regenerate_music",  as: :order_chat_regenerate_music
  patch "orders/:order_id/chat/lyrics", to: "order_chat#edit_lyrics", as: :order_chat_edit_lyrics
  post "orders/:order_id/chat/favorite", to: "order_chat#favorite_music", as: :order_chat_favorite_music
  post "orders/:order_id/chat/prepare_audio", to: "order_chat#prepare_audio", as: :order_chat_prepare_audio
  patch "orders/:order_id/chat/sound_settings", to: "order_chat#sound_settings", as: :order_chat_sound_settings
  patch "orders/:order_id/chat/excerpt", to: "order_chat#excerpt_settings", as: :order_chat_excerpt_settings

  get  "songs",                        to: "songs#index",           as: :songs
end
