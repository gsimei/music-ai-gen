module Campaigns
  class UploadMedia < BaseService
    attribute :campaign
    attribute :token, :string
    attribute :photos
    attribute :logo
    attribute :skip, :boolean, default: false

    def call
      campaign.order.with_lock do
        campaign.reload
        return failure_result("Aguarde a confirmação do pagamento.") unless campaign.payment_confirmed?
        return failure_result("Esta seleção não pertence à campanha.") if token.blank? || token != campaign.media_upload_token
        return success_result(campaign) if campaign.media_uploaded_at.present?

        unless skip
          return failure_result("Selecione as fotos novamente.") unless photos.nil? || photos.is_a?(Array)
          uploads = Array(photos).reject(&:blank?)
          return failure_result("Selecione até #{PhotoLimit::INITIAL} fotos.") if uploads.size > PhotoLimit::INITIAL
          return failure_result("Selecione suas imagens ou continue sem imagens.") if uploads.empty? && logo.blank?
          return failure_result("Envie as imagens como arquivos.") unless (uploads + [ logo ].compact_blank).all? { |file| file.is_a?(ActionDispatch::Http::UploadedFile) }
          campaign.photos = uploads if uploads.any?
          campaign.photo = nil if uploads.any?
          campaign.photo_order = [] if uploads.any?
          campaign.logo = logo if logo.present?
        end
        campaign.media_uploaded_at = Time.current
        return failure_result(campaign.errors.full_messages.join(". ")) unless campaign.save
        success_result(campaign)
      end
    end
  end
end
