require "docker-api"
require 'erb'
require 'ostruct'

DEFAULT_PORT = 27017

def build_image(mongo_version, image_type, bindings)
  image_repo = "#{mongo_version}-#{image_type}"
  puts "Building image #{image_repo}"
  template = File.read("./templates/Dockerfile-#{image_type}.erb")
  dockerfile = ERB.new(template).result(bindings)
  image = Docker::Image.build(dockerfile)
  image.tag('repo' => image_repo)
  puts "Image #{image_repo} built"
end

def ensure_image(mongo_version, image_type)
  image_repo = "#{mongo_version}-#{image_type}"
  if Docker::Image.exist?(image_repo)
    puts "Image #{image_repo} exists"
  else
    bindings = OpenStruct.new(mongo_version: mongo_version).instance_eval { binding }
    build_image(mongo_version, "base", bindings) unless Docker::Image.exist?("#{mongo_version}-base")
    build_image(mongo_version, image_type, bindings)
  end
  image_repo
end

def run_standalone(mongo_version)
  puts "Starting mongo version #{mongo_version} in standalone mode"
  image_repo = ensure_image(mongo_version, "standalone")
  puts "Starting docker image #{image_repo}"
  c = Docker::Container.create(
    'Image' => image_repo,
    'HostConfig' => {
      'PortBindings' => {
        "#{DEFAULT_PORT}/tcp" => [{ 'HostPort' => DEFAULT_PORT.to_s }]
      }
    }
  )
  c.start
end

def run_replicaset(mongo_version)
  puts "Starting mongo version #{mongo_version} in replica set mode"
  network = Docker::Network.create('mongo-rs')
  image_repo = ensure_image(mongo_version, "replicaset")
  primary = nil
  0.upto(2) do |i|
    c = Docker::Container.create(
      'name' => "mongo-#{i}",
      'Image' => image_repo,
      'HostConfig' => {
        'PortBindings' => {
          "#{DEFAULT_PORT}/tcp" => [{ 'HostPort' => "#{DEFAULT_PORT + i}" }]
        }
      }
    )
    c.start
    network.connect(c.id)
    primary = c if primary.nil?
  end
  primary.store_file(
    "/replicaSet.js",
<<x
config = {
  	"_id" : "rs0",
  	"members" : [
  		{
  			"_id" : 0,
  			"host" : "mongo-0:27017"
  		},
  		{
  			"_id" : 1,
  			"host" : "mongo-1:27017"
  		},
  		{
  			"_id" : 2,
  			"host" : "mongo-2:27017"
  		}
  	]
  }
rs.initiate(config)
x
  )
  primary.exec(%w[mongo localhost:27017/test /replicaSet.js])
end

mongo_version = ARGV[0]

if mongo_version.nil?
  puts "Please specify a version"
  exit(-1)
end

mongo_topology = ARGV[1]

if mongo_topology.nil?
  puts "Please specify a topology"
  exit(-1)
end

case mongo_topology
when 'standalone'
  run_standalone(mongo_version)
when 'replicaset'
  run_replicaset(mongo_version)
else
  puts "Unknown topology"
end
