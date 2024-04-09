require 'erb'
require 'yaml'

require_relative 'buildsystem'

BUILD_CONFIG = YAML.safe_load(ERB.new(IO.read("build.yml")).result, symbolize_names: true)

Rake.add_rakelib './build/tasks'

at_exit do
  BuildSystem::CommandLogger.out
end
