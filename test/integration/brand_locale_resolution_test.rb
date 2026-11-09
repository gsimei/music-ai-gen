# frozen_string_literal: true

require "test_helper"

class BrandLocaleResolutionTest < ActionDispatch::IntegrationTest
  class TestProbeController < ApplicationController
    skip_forgery_protection
    skip_before_action :authenticate_user!

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

  test "host jinglepro.it detecta brand b2b e forca locale it" do
    host! "jinglepro.it"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2b locale=pt", response.body
  end

  test "host b2b.lvh.me detecta brand b2b e locale it por default" do
    host! "b2b.lvh.me"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2b locale=pt", response.body
  end

  test "qualquer host detecta brand b2b" do
    host! "jinglepro.com"
    get "/test_probe", headers: { "Accept-Language" => "en-US,en;q=0.9" }
    assert_response :success
    assert_equal "brand=b2b locale=pt", response.body
  end

  test "cookie locale fr resulta em brand b2b locale fr" do
    host! "b2b.lvh.me"
    cookies[:locale] = "fr"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2b locale=pt", response.body
  end

  test "request com Accept-Language detectado seta cookie de locale" do
    host! "jinglepro.com"
    get "/test_probe", headers: { "Accept-Language" => "de,en;q=0.8" }
    assert_response :success
    assert_equal "brand=b2b locale=pt", response.body
    assert_equal "pt", cookies[:locale]
  end

  test "request com locale ja no cookie nao reescreve o cookie" do
    host! "jinglepro.com"
    cookies[:locale] = "en"
    get "/test_probe"
    assert_response :success
    assert_equal "brand=b2b locale=pt", response.body
    assert_equal "pt", cookies[:locale]
  end
end
