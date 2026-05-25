# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_25_101100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "briefings", force: :cascade do |t|
    t.text "about", null: false
    t.text "avoid"
    t.datetime "created_at", null: false
    t.jsonb "extra_params", default: {}
    t.text "keywords"
    t.string "language", default: "it", null: false
    t.string "mood"
    t.string "music_style", null: false
    t.string "occasion"
    t.bigint "order_id", null: false
    t.string "recipient"
    t.integer "target_duration_seconds", default: 120
    t.string "tempo"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "voice_id"
    t.index ["music_style"], name: "index_briefings_on_music_style"
    t.index ["occasion"], name: "index_briefings_on_occasion"
    t.index ["order_id"], name: "index_briefings_on_order_id", unique: true
    t.index ["voice_id"], name: "index_briefings_on_voice_id"
  end

  create_table "email_deliveries", force: :cascade do |t|
    t.string "brand", null: false
    t.datetime "clicked_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "locale", null: false
    t.datetime "opened_at"
    t.bigint "order_id"
    t.string "provider_message_id"
    t.string "recipient_email", null: false
    t.datetime "sent_at"
    t.string "status", default: "queued"
    t.string "template", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["order_id", "template"], name: "index_email_deliveries_on_order_id_and_template"
    t.index ["order_id"], name: "index_email_deliveries_on_order_id"
    t.index ["status"], name: "index_email_deliveries_on_status"
    t.index ["user_id"], name: "index_email_deliveries_on_user_id"
  end

  create_table "generation_jobs", force: :cascade do |t|
    t.integer "attempt_count", default: 0
    t.decimal "cost_usd", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "finished_at"
    t.integer "input_tokens"
    t.integer "latency_ms"
    t.bigint "lyrics_draft_id"
    t.string "model", null: false
    t.bigint "order_id", null: false
    t.integer "output_tokens"
    t.string "prompt_version"
    t.string "provider", null: false
    t.jsonb "request_payload", default: {}
    t.jsonb "response_payload", default: {}
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.string "step", null: false
    t.integer "total_tokens"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_generation_jobs_on_created_at"
    t.index ["lyrics_draft_id"], name: "index_generation_jobs_on_lyrics_draft_id"
    t.index ["order_id", "step"], name: "index_generation_jobs_on_order_id_and_step"
    t.index ["order_id"], name: "index_generation_jobs_on_order_id"
    t.index ["status"], name: "index_generation_jobs_on_status"
  end

  create_table "lyrics_drafts", force: :cascade do |t|
    t.datetime "approved_at"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.boolean "is_approved", default: false, null: false
    t.boolean "is_locked", default: false, null: false
    t.integer "latency_ms"
    t.string "llm_model"
    t.string "llm_provider"
    t.bigint "order_id", null: false
    t.integer "output_tokens"
    t.bigint "parent_draft_id"
    t.string "prompt_version"
    t.string "source", null: false
    t.jsonb "structure", default: {}
    t.datetime "updated_at", null: false
    t.text "user_feedback"
    t.integer "version", null: false
    t.index ["order_id", "is_approved"], name: "index_lyrics_drafts_on_order_id_and_is_approved"
    t.index ["order_id", "version"], name: "index_lyrics_drafts_on_order_id_and_version", unique: true
    t.index ["order_id"], name: "index_lyrics_drafts_on_order_id"
    t.index ["parent_draft_id"], name: "index_lyrics_drafts_on_parent_draft_id"
  end

  create_table "music_generations", force: :cascade do |t|
    t.integer "attempt_count", default: 0
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.string "feedback_type"
    t.integer "iteration", null: false
    t.bigint "lyrics_draft_id", null: false
    t.string "mood"
    t.string "music_style", null: false
    t.bigint "order_id", null: false
    t.bigint "parent_generation_id"
    t.string "provider", null: false
    t.string "provider_model"
    t.string "provider_task_id"
    t.datetime "ready_at"
    t.jsonb "request_payload", default: {}
    t.jsonb "response_payload", default: {}
    t.string "status", default: "pending", null: false
    t.datetime "submitted_at"
    t.integer "target_duration_seconds"
    t.string "tempo"
    t.integer "total_latency_ms"
    t.datetime "updated_at", null: false
    t.text "user_feedback"
    t.integer "variant_a_duration_ms"
    t.string "variant_a_full_url"
    t.string "variant_a_preview_url"
    t.string "variant_a_provider_song_id"
    t.string "variant_a_stems_url"
    t.integer "variant_b_duration_ms"
    t.string "variant_b_full_url"
    t.string "variant_b_preview_url"
    t.string "variant_b_provider_song_id"
    t.string "variant_b_stems_url"
    t.bigint "voice_id", null: false
    t.index ["lyrics_draft_id"], name: "index_music_generations_on_lyrics_draft_id"
    t.index ["order_id", "iteration"], name: "index_music_generations_on_order_id_and_iteration", unique: true
    t.index ["order_id"], name: "index_music_generations_on_order_id"
    t.index ["parent_generation_id"], name: "index_music_generations_on_parent_generation_id"
    t.index ["provider_task_id"], name: "index_music_generations_on_provider_task_id"
    t.index ["status"], name: "index_music_generations_on_status"
    t.index ["voice_id"], name: "index_music_generations_on_voice_id"
  end

  create_table "order_assets", force: :cascade do |t|
    t.string "checksum_sha256"
    t.datetime "created_at", null: false
    t.integer "download_count", default: 0
    t.integer "file_size_bytes"
    t.string "kind", null: false
    t.datetime "last_downloaded_at"
    t.string "mime_type"
    t.bigint "music_generation_id"
    t.bigint "order_id", null: false
    t.string "storage_key", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.datetime "url_expires_at"
    t.index ["music_generation_id"], name: "index_order_assets_on_music_generation_id"
    t.index ["order_id", "kind"], name: "index_order_assets_on_order_id_and_kind"
    t.index ["order_id"], name: "index_order_assets_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_lyrics_draft_id"
    t.bigint "approved_music_generation_id"
    t.string "approved_variant"
    t.string "brand", null: false
    t.string "cancellation_reason"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "EUR", null: false
    t.datetime "delivered_at"
    t.string "delivery_email", null: false
    t.integer "download_count", default: 0
    t.datetime "first_download_at"
    t.text "internal_notes"
    t.string "locale", default: "it", null: false
    t.integer "lyrics_regen_limit", default: 3, null: false
    t.integer "lyrics_regen_used", default: 0, null: false
    t.integer "music_regen_limit", default: 2, null: false
    t.integer "music_regen_used", default: 0, null: false
    t.datetime "paid_at"
    t.integer "price_cents", null: false
    t.string "reference", null: false
    t.string "status", default: "pending", null: false
    t.string "stripe_charge_id"
    t.string "stripe_payment_intent_id"
    t.string "stripe_session_id"
    t.string "tier", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["approved_lyrics_draft_id"], name: "index_orders_on_approved_lyrics_draft_id"
    t.index ["approved_music_generation_id"], name: "index_orders_on_approved_music_generation_id"
    t.index ["brand", "status"], name: "index_orders_on_brand_and_status"
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["paid_at"], name: "index_orders_on_paid_at"
    t.index ["reference"], name: "index_orders_on_reference", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_orders_on_stripe_payment_intent_id"
    t.index ["stripe_session_id"], name: "index_orders_on_stripe_session_id"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "refund_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.text "reason", null: false
    t.string "reason_category"
    t.integer "refunded_amount_cents"
    t.text "resolution_notes"
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.string "status", default: "pending"
    t.string "stripe_refund_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["order_id"], name: "index_refund_requests_on_order_id"
    t.index ["resolved_by_id"], name: "index_refund_requests_on_resolved_by_id"
    t.index ["status"], name: "index_refund_requests_on_status"
    t.index ["user_id"], name: "index_refund_requests_on_user_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.integer "attempt_count", default: 0
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_type", null: false
    t.bigint "order_id"
    t.jsonb "payload", null: false
    t.datetime "processed_at"
    t.string "status", default: "pending"
    t.string "stripe_event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_stripe_events_on_event_type"
    t.index ["order_id"], name: "index_stripe_events_on_order_id"
    t.index ["status"], name: "index_stripe_events_on_status"
    t.index ["stripe_event_id"], name: "index_stripe_events_on_stripe_event_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.boolean "guest", default: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale", default: "it", null: false
    t.datetime "locked_at"
    t.string "name"
    t.string "origin_brand"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "customer"
    t.integer "sign_in_count", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["origin_brand"], name: "index_users_on_origin_brand"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["stripe_customer_id"], name: "index_users_on_stripe_customer_id"
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "voices", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "allowed_brands", default: ["b2b", "b2c"], array: true
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "display_order", default: 0
    t.string "external_id"
    t.string "gender"
    t.string "language_tags", default: [], array: true
    t.integer "min_tier", default: 0
    t.string "mood_tags", default: [], array: true
    t.string "mureka_prompt"
    t.string "name", null: false
    t.string "provider", null: false
    t.string "sample_audio_url"
    t.string "slug", null: false
    t.string "style_tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_voices_on_active"
    t.index ["display_order"], name: "index_voices_on_display_order"
    t.index ["provider", "external_id"], name: "index_voices_on_provider_and_external_id", unique: true
    t.index ["slug"], name: "index_voices_on_slug", unique: true
  end

  add_foreign_key "briefings", "orders"
  add_foreign_key "briefings", "voices"
  add_foreign_key "email_deliveries", "orders"
  add_foreign_key "email_deliveries", "users"
  add_foreign_key "generation_jobs", "lyrics_drafts"
  add_foreign_key "generation_jobs", "orders"
  add_foreign_key "lyrics_drafts", "lyrics_drafts", column: "parent_draft_id"
  add_foreign_key "lyrics_drafts", "orders"
  add_foreign_key "music_generations", "lyrics_drafts"
  add_foreign_key "music_generations", "music_generations", column: "parent_generation_id"
  add_foreign_key "music_generations", "orders"
  add_foreign_key "music_generations", "voices"
  add_foreign_key "order_assets", "music_generations"
  add_foreign_key "order_assets", "orders"
  add_foreign_key "orders", "lyrics_drafts", column: "approved_lyrics_draft_id"
  add_foreign_key "orders", "music_generations", column: "approved_music_generation_id"
  add_foreign_key "orders", "users"
  add_foreign_key "refund_requests", "orders"
  add_foreign_key "refund_requests", "users"
  add_foreign_key "refund_requests", "users", column: "resolved_by_id"
  add_foreign_key "stripe_events", "orders"
end
