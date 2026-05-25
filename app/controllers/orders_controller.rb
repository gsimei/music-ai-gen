# frozen_string_literal: true

class OrdersController < ApplicationController
  # TODO: add skip_authorization when Pundit verify_authorized is enabled (ROADMAP M-6)

  def new
    wizard = Orders::WizardSession.new(session)
    wizard.clear!
    redirect_to wizard_order_path(step: 1)
  end

  def show
    @order = Order.find(params[:id])
  end

  def wizard_show
    step = params[:step].to_i
    wizard = Orders::WizardSession.new(session)

    unless wizard.step_accessible?(step)
      redirect_to wizard_order_path(step: 1) and return
    end

    @step = step
    @wizard_session = wizard
    load_step_resources(step)
    render "orders/wizard/step_#{step}"
  end

  def wizard_update
    step = params[:step].to_i
    step_params = params.require(:order_wizard).permit!.to_h.symbolize_keys

    validator = Orders::StepValidator.new(
      step:   step,
      brand:  @current_brand,
      params: step_params
    )

    unless validator.valid?
      @step = step
      @validator = validator
      @wizard_session = Orders::WizardSession.new(session)
      load_step_resources(step)
      render "orders/wizard/step_#{step}", status: :unprocessable_entity
      return
    end

    wizard = Orders::WizardSession.new(session)

    if step == 3
      wizard.update!(step_params, step: 3)
    else
      wizard.update!(step_params)
    end

    if step < 5
      redirect_to wizard_order_path(step: step + 1)
    else
      result = Orders::CreateDraftService.call(
        brand:       @current_brand,
        locale:      I18n.locale.to_s,
        user_id:     current_user&.id,
        wizard_data: wizard.to_h.merge(step_params)
      )

      if result.success?
        wizard.clear!
        redirect_to order_path(result.value)
      else
        @step = step
        @validator = validator
        @wizard_session = wizard
        render "orders/wizard/step_#{step}", status: :unprocessable_entity
      end
    end
  end

  private

  def load_step_resources(step)
    case step
    when 4
      @voices = Voice.active.for_brand(@current_brand.to_s).ordered
    when 5
      @voices = Voice.active.for_brand(@current_brand.to_s).ordered
      @brand_config = BRANDS_CONFIG[@current_brand.to_sym]
    end
  end
end
