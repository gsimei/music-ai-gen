require_relative "boot"

require "rails/all"
require_relative "../lib/soundtrack_request_limit"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MusicAiGen
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1
    config.middleware.insert_before 0, SoundtrackRequestLimit

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # I18n — todos os idiomas suportados pela plataforma
    config.i18n.available_locales = %i[it en es fr de pt]
    config.i18n.default_locale = :pt
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.yml").to_s]

    # Marked previews (CampaignAudioController) are played in the page, not
    # downloaded. Stock storage routes for order audio stay blocked by ProtectedOrderAudio.
    config.active_storage.content_types_allowed_inline += %w[audio/mp4]
  end
end
