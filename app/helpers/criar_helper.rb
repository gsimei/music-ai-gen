module CriarHelper
  # Campo do Criar com erro de validação: aria-invalid + aria-describedby com a dica e a mensagem (D9).
  # help_id pode ter mais de um id, separados por espaço, ou ser nil.
  def criar_field_aria(record, attribute, help_id = nil)
    return { describedby: help_id } if record.errors[attribute].empty?

    { describedby: [ help_id, criar_error_id(attribute) ].compact.join(" "), invalid: "true" }
  end

  def criar_field_error(record, attribute)
    messages = record.errors.full_messages_for(attribute)
    tag.p(messages.to_sentence, id: criar_error_id(attribute), class: "ui-error") if messages.any?
  end

  private

  def criar_error_id(attribute)
    "campaign-#{attribute.to_s.dasherize}-error"
  end
end
