require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "importmaps receive fresh script nonces while inline handlers remain forbidden" do
    get root_path
    assert_response :success
    policy = response.headers.fetch("Content-Security-Policy")
    scripts = policy.split(";").find { |directive| directive.strip.start_with?("script-src ") }
    nonce = scripts[/'nonce-([^']+)'/, 1]
    assert nonce.present?
    refute_includes scripts, "unsafe-inline"
    refute_includes scripts, "unsafe-eval"
    assert_select 'script[type="importmap"][nonce=?]', nonce
    assert_includes policy, "img-src 'self' data: blob:"
    assert_includes policy, "form-action 'self' https://checkout.stripe.com"
    assert_includes policy, "frame-ancestors 'none'"
    styles = policy.split(";").find { |directive| directive.strip.start_with?("style-src ") }
    assert_includes styles, "'unsafe-inline'"
    refute_includes styles, "nonce-"
    get root_path
    refute_includes response.headers.fetch("Content-Security-Policy"), "'nonce-#{nonce}'"
  end
end
