# frozen_string_literal: true

desc 'Setup the project'
task setup: %w[init build] do
end

desc 'Refresh environment'
task refresh: %w[down setup] do
end

desc 'Initializes local docker dev environment'
task :init do
  dcp = YAML.safe_load(IO.read(File.join('./', 'docker-compose.yml')))&.with_indifferent_access
  files = dcp[:services].map { |_, service| service[:env_file] }.flatten(1).filter { |item| !item.nil? && !item.empty? }
  files.each { |file| BuildSystem.system "touch #{file}" }
end

desc 'Kill all Docker Services'
task :kill do
  BuildSystem.logger.info 'Killing all docker services'
  BuildSystem.system! 'docker kill $(docker ps -q)'
end

desc 'Nuke Docker Environment'
task nuke: [:down] do
  BuildSystem.logger.info 'Wiping docker environment'
  BuildSystem.system! 'docker system prune -a --volumes'
end

desc 'Stop all Services'
task stop: [] do |_, args|
  args.with_defaults(service: nil)
  BuildSystem.system! "docker compose stop"
end

desc 'Tear Down Environment'
task down: [] do
  BuildSystem.system! 'docker compose down'
end


namespace :build do
  BuildSystem.projects.each do |project, _project_config|
    desc "Build #{project}"
    task project do
      BuildSystem.logger.info "Building #{project}"
      BuildSystem.system! "docker compose build #{project}"
    end
  end
end

namespace :start do
  BuildSystem.projects.each do |project, _project_config|
    desc "Start #{project}"
    task project do
      BuildSystem.logger.info "Starting #{project}"
      BuildSystem.system! "docker compose up #{project}"
    end
  end
end

namespace :stop do
  BuildSystem.projects.each do |project, _project_config|
    desc "Stop #{project}"
    task project do
      BuildSystem.logger.info "Stopping #{project}"
      BuildSystem.system! "docker compose stop #{project}"
    end
  end
end

namespace :down do
  BuildSystem.projects.each do |project, _project_config|
    desc "Down #{project}"
    task project do
      BuildSystem.logger.info "Starting #{project}"
      BuildSystem.system! "docker compose down #{project}"
    end
  end
end

namespace :restart do
  BuildSystem.projects.each do |project, _project_config|
    desc "Restart #{project}"
    task project do
      BuildSystem.logger.info "Restarting #{project}"
      BuildSystem.system! "docker compose restart #{project}"
    end
  end
end

namespace :logs do
  BuildSystem.projects.each do |project, _project_config|
    desc "Logs #{project}"
    task project do
      BuildSystem.logger.info "Watching Docker Logs #{project}"
      BuildSystem.system! "docker compose logs -f #{project}"
    end
  end
end

namespace :test do
  BuildSystem.projects.each do |project, _project_config|
    desc "Test #{project}"
    task project do
      BuildSystem.logger.info "Executing Unit Tests for #{project}"
      BuildSystem.system! "docker compose run --rm #{project} bin/test"
    end
  end
end
