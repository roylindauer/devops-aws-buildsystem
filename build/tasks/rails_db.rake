# frozen_string_literal: true

def rails_db_commands(namespace_name, project_name)
  namespace namespace_name do
    task 'dangerous-action' do
      env = ENV['ENV'].to_s
      if !env.empty? && ENV['DANGEROUS_DATABASE_ACTION'].to_s != '1'
        BuildSystem.logger.info "Set DANGEROUS_DATABASE_ACTION=1 to enable this action in #{env}"
        raise "Dangerous database action not allowed in #{env}"
      end
    end

    desc "Create `#{project_name}` if it doesn't exist"
    task create: ['create-if'] do
    end

    task 'create-if' => [] do
      BuildSystem.dcp.run(service: project_name, cmd: 'bin/rails db:create')
    end

    desc "Load `#{project_name}` Schema"
    task schema: [] do
      BuildSystem.dcp.run(service: project_name, cmd: 'bin/rails db:schema:load')
    end

    desc "Drop `#{project_name}`"
    task drop: ['dangerous-action'] do
      BuildSystem.dcp.run(service: project_name, cmd: 'bin/rails db:drop')
    end

    desc "Migrate `#{project_name}` to the latest schema"
    task migrate: [] do
      BuildSystem.dcp.run(service: project_name, cmd: 'bin/rails db:migrate')
    end

    desc "Seed `#{project_name}`"
    task seed: [] do
      BuildSystem.dcp.run(service: project_name, cmd: 'bin/rails db:seed')
    end

    desc "Load `#{project_name}` fixtures"
    task fixtures: [] do
      BuildSystem.dcp.run(service: project_name, cmd: 'bin/rails db:fixtures:load')
    end

    desc "Reset `#{project_name}`"
    task reset: %w[drop setup].map { |i| "#{namespace_name}:#{i}" } do
    end

    desc 'Setup'
    task setup: [] do
      cmd = [
        'bin/wait-for-it -t 0 mysql:3306 --',
        'bin/rails',
        'db:setup'
      ]

      BuildSystem.dcp.run(service: project_name, cmd: cmd.join(' '))
    end
  end
end

rails_db_commands('railsproject_db', 'railsproject')
