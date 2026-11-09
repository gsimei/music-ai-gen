# frozen_string_literal: true

require "test_helper"

class BrandLocaleResolverTest < ActiveSupport::TestCase
  class DevResolver < BrandLocaleResolver
    def rails_env = ActiveSupport::EnvironmentInquirer.new("development")
  end

  class ProdResolver < BrandLocaleResolver
    def rails_env = ActiveSupport::EnvironmentInquirer.new("production")
  end

  # ---------------------------------------------------------------------------
  # Brand always resolves to b2b regardless of host
  # ---------------------------------------------------------------------------

  test "any host detecta brand b2b" do
    result = BrandLocaleResolver.call(host: "jinglepro.it")
    assert result.success?
    assert_equal "b2b", result.value[:brand]
  end

  test "host desconhecido retorna brand b2b" do
    result = BrandLocaleResolver.call(host: "unknown-host.example.com")
    assert result.success?
    assert_equal "b2b", result.value[:brand]
  end

  # ---------------------------------------------------------------------------
  # Host .it → locale :it forçado
  # ---------------------------------------------------------------------------

  test "host jinglepro.it força locale it" do
    result = BrandLocaleResolver.call(host: "jinglepro.it")
    assert result.success?
    assert_equal :it, result.value[:locale]
  end

  # ---------------------------------------------------------------------------
  # Host .com → default locale do brand
  # ---------------------------------------------------------------------------

  test "host jinglepro.com sem sinais retorna locale default pt" do
    result = BrandLocaleResolver.call(host: "jinglepro.com")
    assert result.success?
    assert_equal :pt, result.value[:locale]
  end

  # ---------------------------------------------------------------------------
  # Accept-Language
  # ---------------------------------------------------------------------------

  test "Accept-Language en-US,en;q=0.9 retorna locale en" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      accept_language: "en-US,en;q=0.9"
    )
    assert result.success?
    assert_equal :en, result.value[:locale]
  end

  test "Accept-Language com idioma nao suportado cai no default" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      accept_language: "zh-CN,zh;q=0.9"
    )
    assert result.success?
    assert_equal :pt, result.value[:locale]
  end

  test "Accept-Language de-AT,de;q=0.9,it;q=0.8 retorna de" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      accept_language: "de-AT,de;q=0.9,it;q=0.8"
    )
    assert result.success?
    assert_equal :de, result.value[:locale]
  end

  # ---------------------------------------------------------------------------
  # Cookie de locale
  # ---------------------------------------------------------------------------

  test "cookie locale fr valido retorna fr" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      locale_cookie: "fr"
    )
    assert result.success?
    assert_equal :fr, result.value[:locale]
  end

  test "cookie locale invalido e ignorado e usa Accept-Language" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      locale_cookie: "xx",
      accept_language: "en-GB"
    )
    assert result.success?
    assert_equal :en, result.value[:locale]
  end

  test "cookie invalido sem Accept-Language cai no default" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      locale_cookie: "zz"
    )
    assert result.success?
    assert_equal :pt, result.value[:locale]
  end

  # ---------------------------------------------------------------------------
  # Precedência: cookie > Accept-Language
  # ---------------------------------------------------------------------------

  test "cookie tem precedencia sobre Accept-Language" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      locale_cookie: "es",
      accept_language: "en-US,en;q=0.9"
    )
    assert result.success?
    assert_equal :es, result.value[:locale]
  end

  # ---------------------------------------------------------------------------
  # locale_param — apenas em development
  # ---------------------------------------------------------------------------

  test "locale_param de em test env nao e aplicado — cai no default" do
    result = BrandLocaleResolver.call(
      host: "jinglepro.com",
      locale_param: "de"
    )
    assert result.success?
    assert_equal :pt, result.value[:locale]
  end

  test "locale_param em production e ignorado — host .it ainda força it" do
    result = ProdResolver.call(
      host: "jinglepro.it",
      locale_param: "de"
    )
    assert result.success?
    assert_equal :it, result.value[:locale]
  end

  test "locale_param de em development tem precedencia sobre cookie" do
    result = DevResolver.call(
      host: "jinglepro.com",
      locale_param: "de",
      locale_cookie: "es"
    )
    assert result.success?
    assert_equal :de, result.value[:locale]
  end

  test "locale_param tem precedencia sobre cookie em development" do
    result = DevResolver.call(
      host: "b2b.lvh.me",
      locale_param: "fr",
      locale_cookie: "en",
      accept_language: "de"
    )
    assert result.success?
    assert_equal :fr, result.value[:locale]
  end

  # ---------------------------------------------------------------------------
  # Normalização de host
  # ---------------------------------------------------------------------------

  test "host com porta jinglepro.it:3000 normaliza e detecta brand b2b" do
    result = BrandLocaleResolver.call(host: "jinglepro.it:3000")
    assert result.success?
    assert_equal "b2b", result.value[:brand]
    assert_equal :it, result.value[:locale]
  end

  test "host com www www.jinglepro.com normaliza e detecta brand b2b" do
    result = BrandLocaleResolver.call(host: "www.jinglepro.com")
    assert result.success?
    assert_equal "b2b", result.value[:brand]
  end

  # ---------------------------------------------------------------------------
  # host vazio / nil — validacao
  # ---------------------------------------------------------------------------

  test "host vazio retorna failure_result com validation error" do
    result = BrandLocaleResolver.call(host: "")
    assert result.failure?
    assert result.errors.is_a?(ActiveModel::Errors)
    assert result.errors[:host].any?
  end

  test "host nil retorna failure_result com validation error" do
    result = BrandLocaleResolver.call(host: nil)
    assert result.failure?
    assert result.errors.is_a?(ActiveModel::Errors)
    assert result.errors[:host].any?
  end
end
