# frozen_string_literal: true

# Carrega config/brands.yml e congela recursivamente a constante global.
# Acesso com simbolos: BRANDS_CONFIG[:b2b][:display_name]
#
# Nota: usamos YAML.safe_load + deep_symbolize_keys porque o brands.yml nao segue
# a convencao de chaves por ambiente (development/production) que config_for espera.
# Brands sao configuracao de negocio, nao de ambiente.
#
# deep_freeze e recursivo: Object#freeze do Ruby e shallow, deixando hashes aninhados
# mutaveis. Em ambiente multi-threaded (Puma), mutacao acidental de constante global
# e fonte de bugs dificeis de rastrear.
def deep_freeze(obj)
  case obj
  when Hash
    obj.each_value { |v| deep_freeze(v) }
  when Array
    obj.each { |v| deep_freeze(v) }
  end
  obj.freeze
end

brands_path = Rails.root.join("config", "brands.yml")
BRANDS_CONFIG = deep_freeze(YAML.safe_load(File.read(brands_path)).deep_symbolize_keys)
