require "net/http"
require "resolv"
require "ipaddr"
require "timeout"

module Campaigns
  class AudioDownload
    def self.call(url, destination)
      uri = URI.parse(url)
      raise "Endereço de áudio inválido" unless uri.is_a?(URI::HTTPS) && uri.host && uri.userinfo.nil?
      address = Resolv.getaddress(uri.host)
      ip = IPAddr.new(address)
      forbidden = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8 ::ffff:0:0/96]
      raise "Endereço de áudio inválido" if forbidden.any? { |range| IPAddr.new(range).include?(ip) }
      http = Net::HTTP.new(uri.host, uri.port)
      http.ipaddr = address
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30
      Timeout.timeout(90) do
        http.start do |connection|
          connection.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
            raise "Não foi possível baixar a música" unless response.is_a?(Net::HTTPSuccess)
            size = 0
            File.open(destination, "wb") do |file|
              response.read_body do |chunk|
                size += chunk.bytesize
                raise "Áudio muito grande" if size > 30.megabytes
                file.write(chunk)
              end
            end
          end
        end
      end
    end
  end
end
