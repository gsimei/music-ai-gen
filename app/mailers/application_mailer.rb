class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.config.x.mailer_from.presence || "ViraJingle <no-reply@virajingle.test>" }
  layout "mailer"
end
