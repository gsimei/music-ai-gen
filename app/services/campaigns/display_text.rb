module Campaigns
  class DisplayText
    def self.call(value)
      value.to_s.gsub(/\r\n?/, "\n").gsub(/R\$[^\S\r\n]*(?=\d)/, "R$\u00a0")
    end
  end
end
