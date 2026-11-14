require "tempfile"

# Bound upload ingress before Rails/Rack parses multipart files into tempfiles.
class SoundtrackRequestLimit
  MAX_BYTES = 101 * 1024 * 1024 # Advertised 100 MiB file plus bounded multipart overhead.
  ROUTES = %r{\A/orders/[^/]+/(?:soundtrack|chat)(?:\.[^/]+)?/?\z}

  def initialize(app, limit: MAX_BYTES)
    @app = app
    @limit = limit
  end

  def call(env)
    path = ActionDispatch::Journey::Router::Utils.normalize_path(Rack::Utils.unescape_path(env["PATH_INFO"].to_s))
    return @app.call(env) unless env["REQUEST_METHOD"] == "POST" && ROUTES.match?(path)
    return too_large if env["CONTENT_LENGTH"].to_i > @limit

    # Enforce actual bytes too: absent or misleading Content-Length is not trusted.
    Tempfile.create([ "soundtrack-request", ".body" ], binmode: true) do |body|
      while (chunk = env["rack.input"].read([ 64 * 1024, @limit - body.size + 1 ].min)) && !chunk.empty?
        return too_large if body.size + chunk.bytesize > @limit
        body.write(chunk)
      end
      body.rewind
      env["rack.input"] = body
      @app.call(env)
    end
  end

  private

  def too_large
    [ 413, { "content-type" => "text/plain" }, [ "Upload too large" ] ]
  end
end
