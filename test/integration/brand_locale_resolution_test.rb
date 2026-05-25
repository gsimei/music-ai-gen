# frozen_string_literal: true

require "test_helper"

# Testa o fluxo completo de resolucao de brand+locale via around_action do ApplicationController.
# Usa um controller de probe definido localmente para inspecionar o estado interno
# da request (current_brand e I18n.locale) sem poluir o routes.rb de producao.
class BrandLocaleResolutionTest < ActionDispatch::IntegrationTest
  # Controller stub que renderiza brand e locale como plain text para inspeção.
  class TestProbeController < ApplicationController
    skip_forgery_protection

    def probe
      render plain: "brand=#{@current_brand} locale=#{I18n.locale}"
    end
  end

  setup do
    Rails.application.routes.draw do
      get "/test_probe", to: "brand_locale_resolution_test/test_probe#probe"
      devise_for :users
      get "up" => "rails/health#show", as: :rails_health_check
    end
  end

  teardown do
    Rails.application.reload_routes!
    I18n.locale = I18n.default_locale
  end

  # ---------------------------------------------------------------------------
  # Brand e locale por host
  # ---------------------------------------------------------------------------

  test "host jinglepro.it detecta brand b2b e forca locale it" do
    host! "jinglepro.it"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2b locale=it", response.body
  end

  test "host musicaregalo.com com Accept-Language en detecta brand b2c e locale en" do
    host! "musicaregalo.com"
    get "/test_probe", headers: { "Accept-Language" => "en-US,en;q=0.9" }
    assert_response :success
    assert_equal "brand=b2c locale=en", response.body
  end

  test "host b2b.lvh.me detecta brand b2b e locale it por default" do
    host! "b2b.lvh.me"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2b locale=it", response.body
  end

  # ---------------------------------------------------------------------------
  # Cookie de locale
  # ---------------------------------------------------------------------------

  test "cookie locale fr para host b2c.lvh.me resulta em brand b2c locale fr" do
    host! "b2c.lvh.me"
    cookies[:locale] = "fr"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2c locale=fr", response.body
  end

  # ---------------------------------------------------------------------------
  # Cookie e setado automaticamente quando locale e detectado por Accept-Language
  # ---------------------------------------------------------------------------

  test "request com Accept-Language detectado seta cookie de locale" do
    host! "musicaregalo.com"
    get "/test_probe", headers: { "Accept-Language" => "de,en;q=0.8" }
    assert_response :success
    assert_equal "brand=b2c locale=de", response.body
    # Cookie deve ser setado com o locale detectado
    assert_equal "de", cookies[:locale]
  end

  test "request com locale ja no cookie nao reescreve o cookie" do
    host! "musicaregalo.com"
    cookies[:locale] = "en"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2c locale=en", response.body
    # Cookie nao e reescrito (mesmo valor)
    assert_equal "en", cookies[:locale]
  end
end
