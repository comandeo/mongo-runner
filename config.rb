require 'yaml'

class  Config
  FILENAME = File.join(Dir.home, ".mongo-runner")

  def self.with_config
    config = load
    yield config
  ensure
    save(config)
  end

  def self.load
    if File.file?(FILENAME)
      YAML.load_file(FILENAME)
    else
      {}
    end
  end

  def self.save(cfg)
    File.open(FILENAME, "w") do |f|
      f.write(cfg.to_yaml)
    end
  end
end