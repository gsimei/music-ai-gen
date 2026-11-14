require "test_helper"

class SoundtrackRequestLimitTest < ActiveSupport::TestCase
  test "request budget allows one maximum file plus multipart overhead" do
    assert_equal SoundtrackInput::MAX_FILE_SIZE + 1.megabyte, SoundtrackRequestLimit::MAX_BYTES
  end

  test "oversized declared body is rejected without reading or parsing it" do
    input = Object.new
    def input.read(*) = raise("must not read oversized request")
    response = SoundtrackRequestLimit.new(->(_) { flunk "request reached app" }, limit: 8).call(
      env(input, "CONTENT_LENGTH" => "9"))
    assert_equal 413, response.first
  end

  test "missing and forged content lengths cannot bypass actual streamed byte limit" do
    [ nil, "1" ].each do |length|
      response = SoundtrackRequestLimit.new(->(_) { flunk "request reached app" }, limit: 8).call(
        env(StringIO.new("123456789"), "CONTENT_LENGTH" => length))
      assert_equal 413, response.first
    end
  end

  test "encoded route and format suffix are still bounded" do
    response = SoundtrackRequestLimit.new(->(_) { flunk "request reached app" }, limit: 8).call(
      env(StringIO.new("123456789"), "PATH_INFO" => "/orders/123/ch%61t.turbo_stream"))
    assert_equal 413, response.first
  end

  test "duplicate slashes normalized by Rails cannot bypass the limit" do
    [ "/orders//123/soundtrack", "/orders/123//chat", "/orders/123/chat//" ].each do |path|
      response = SoundtrackRequestLimit.new(->(_) { flunk "request reached app" }, limit: 8).call(
        env(StringIO.new("123456789"), "PATH_INFO" => path))
      assert_equal 413, response.first
    end
  end

  test "allowed body remains readable and rewindable for the multipart parser" do
    body = nil
    app = ->(request) {
      body = request.fetch("rack.input")
      assert_equal "12345678", body.read
      body.rewind
      assert_equal "123", body.read(3)
      [ 200, {}, [] ]
    }
    assert_equal 200, SoundtrackRequestLimit.new(app, limit: 8).call(env(StringIO.new("12345678"))).first
    assert body.closed?
  end

  test "other campaign photo routes keep their separate upload limits" do
    input = StringIO.new("123456789")
    app = ->(request) { assert_same input, request["rack.input"]; [ 200, {}, [] ] }
    assert_equal 200, SoundtrackRequestLimit.new(app, limit: 8).call(
      env(input, "PATH_INFO" => "/orders/123/chat/video_photos")).first
  end

  private

  def env(input, overrides = {})
    { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/orders/123/soundtrack", "rack.input" => input }.merge(overrides)
  end
end
