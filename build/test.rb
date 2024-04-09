require 'erb'
require 'yaml'
require 'minitest/autorun'

require_relative 'buildsystem'
require_relative 'tests/helpers'

# BUILD_CONFIG = YAML.safe_load(ERB.new(IO.read("build.yml")).result, symbolize_names: true)

Dir.glob(BuildSystem.build_dir + '/tests/src/*.rb').sort.each { |dependency| require_relative dependency }
