require "net/http"
require "json"
root = Rails.root.join("output/campaigns/2026-11-13-lancamento")
destination = root.join("fontes/transcricao-conferencia.json")
if destination.exist?
  puts destination.read
  exit
end
uri = URI("https://api.openai.com/v1/audio/transcriptions")
request = Net::HTTP::Post.new(uri)
request["Authorization"] = "Bearer #{ENV.fetch('OPENAI_API_KEY')}"
File.open(root.join("audio/virajingle-jingle-27s.m4a"), "rb") do |file|
  request.set_form([["model", "whisper-1"], ["file", file, {filename: "virajingle-jingle.m4a", content_type: "audio/mp4"}], ["language", "pt"], ["response_format", "verbose_json"], ["prompt", "Jingle publicitário brasileiro da marca ViraJingle. Roupas, sapatos, beleza, fotos, promoção, música e vídeo."]], "multipart/form-data")
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120) { |http| http.request(request) }
  body = JSON.parse(response.body)
  if response.code.to_i == 200
    File.write(destination, JSON.pretty_generate(body))
    puts({http_status: 200, text: body["text"], segments: body["segments"]&.map { |s| s.slice("start", "end", "text") }}.to_json)
  else
    puts({http_status: response.code.to_i, error: body.dig("error", "code")}.to_json)
  end
end
