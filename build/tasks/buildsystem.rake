# frozen_string_literal: true

# :nodoc:
require_relative "../buildsystem"

namespace :buildsystem do
  task :environment do
    raise "You need to set GITHUB_REF_NAME 🤪" unless ENV.key? "GITHUB_REF_NAME"
    raise "You need to set GITHUB_RUN_ID 🤪" unless ENV.key? "GITHUB_RUN_ID"
    raise "You need to set ENC_KEY 🤪" unless ENV.key? "ENC_KEY"

    if ENV.key? "DRY_RUN"
      puts "🚨DRY_RUN is enabled by the presence of the DRY_RUN environment variable"
    end
  end

  namespace :build do
    BuildSystem.projects.each do |project, config|
      desc "Build #{project}"
      task project => %i[environment] do
        BuildSystem.logger.info "Building #{project}"
        BuildSystem.system! "DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build #{BuildSystem.convert_object_to_arg(flag: '--build-arg', args: config[:build_args])} -t #{project} -f ./src/#{project}/Dockerfile ./src/#{project}"
      end
    end
  end

  namespace :tag do
    BuildSystem.projects.each do |project, _config|
      desc "Tag #{project}"
      task project => %i[environment] do
        BuildSystem.logger.info "Tagging #{project}"
        
        BuildSystem.system! "docker tag #{project} #{BuildSystem.docker_image_uri(project)}:#{BuildSystem.build_num}" if BuildSystem.cluster?
        BuildSystem.system! "docker tag #{project} #{BuildSystem.docker_image_uri(project)}:latest"
      end
    end
  end

  namespace :push do
    BuildSystem.projects.each do |project, _config|
      desc "Push #{project}"
      task project => %i[environment] do
        unless BuildSystem.cluster?
          BuildSystem.logger.info "Skipping push for ref:#{BuildSystem.branch} because there is no target cluster"
          next
        end
  
        BuildSystem.logger.info "Pushing #{project}"
        BuildSystem.system! "docker push #{BuildSystem.docker_image_uri(project)}:#{BuildSystem.build_num}"
      end
    end
  end

  namespace :migrate do
    BuildSystem.projects.each do |project, _config|
      desc "Execute Database Migrations for #{project}"
      task project => %i[environment] do
        BuildSystem.logger.info "Database Migrations for #{project}"
        BuildSystem.system! "ssh root@#{BuildSystem.cluster[:ip]} '#{BuildSystem.migrate_command(project).join(' ')}'"
      end
    end
  end

  namespace :deploy do
    BuildSystem.projects.each do |project_name, project_config|
      # if a project has docker_tasks then create a deploy task for each docker_tasks,
      # also create a rollup that deploys all docker_tasks
      if project_config.key?(:docker_tasks)
        project_config[:docker_tasks].each do |task_name, _task_config|
          namespace project_name do
            desc "Deploy `#{task_name}`"
            task task_name => ['environment'] do
              BuildSystem.logger.info "Deploying #{task_name}"

              unless BuildSystem.cluster?
                puts "Skipping deploy of #{project_name} for ref:#{BuildSystem.git_ref} because there is no target cluster"
                next
              end
      
              task_factory = AwsEcsTaskFactory.new(
                service: project_name,
                image: "#{BuildSystem.docker_image_uri}:#{BuildSystem.build_num}",
                cluster: BuildSystem.cluster,
                task_vars: BuildSystem.task_environment(project_config),
                task_definition: BuildSystem.task_definition(project_config)
              )
      
              task_definition = task_factory.task_definition
              container_definition = task_factory.container_definition
      
              ecs_register_task_definition_cmd = BuildSystem::AwsCommands.ecs_register_task_definition(
                task_definition: task_definition,
                container_definition: container_definition,
                tags: BuildSystem.task_tags
              )
      
              puts ecs_register_task_definition_cmd
      
              register_task_ret = BuildSystem.system_return(ecs_register_task_definition_cmd)
      
              BuildSystem.valid_json?(register_task_ret)
              revision = BuildSystem::AwsCommands.parse_task_revision(task: register_task_ret)
      
              ecs_update_service_cmd = BuildSystem::AwsCommands.ecs_update_service(
                service: project_name,
                task_definition: "#{task_definition[:family]}:#{revision}",
                cluster: BuildSystem.cluster
              )
      
              puts ecs_update_service_cmd
      
              BuildSystem.system!(ecs_update_service_cmd)

            end
          end
        end

        # Rollup deploy task to deploy all sub tasks
        desc "Deploy all: #{project_config[:docker_tasks].keys.join(', ')}"
        task project_name => ['environment'] + project_config[:docker_tasks].keys.map { |t| "deploy:#{project_name}:#{t}" } do
        end
      end
    end
   end

  namespace :database_migrations do
    BuildSystem.projects.each do |project_name, _|
      desc "Database Migrations for `#{project_name}`"
      task project_name => %i[environment] do
        unless BuildSystem.cluster?
          puts "Skipping migrate for ref:#{BuildSystem.git_ref} because there is no target cluster"
          next
        end

        task_factory = AwsEcsTaskFactory.new(
          service: "#{BUILD_CONFIG[:build][:image]}-migrate",
          image: "#{BuildSystem.docker_image_uri}:#{BuildSystem.build_num}",
          cluster: BuildSystem.cluster,
          task_vars: BuildSystem.task_environment,
          task_definition: BuildSystem.task_definition,
          command: ["./docker/migrate"]
        )

        task_definition = task_factory.task_definition
        container_definition = task_factory.container_definition

        register_task_ret = BuildSystem.system_return(BuildSystem::AwsCommands.ecs_register_task_definition(
          task_definition: task_definition,
          container_definition: container_definition,
          tags: BuildSystem.task_tags
        ))

        BuildSystem.valid_json?(register_task_ret)
        revision = BuildSystem::AwsCommands.parse_task_revision(task: register_task_ret)

        ecs_run_task = BuildSystem::AwsCommands.ecs_run_task(
          family: "#{task_definition[:family]}:#{revision}",
          cluster: BuildSystem.cluster,
          subnets: BuildSystem.subnets,
          security_groups: BuildSystem.security_groups
        )

        resp = BuildSystem.system_return(ecs_run_task)
        task_arn = BuildSystem::AwsCommands.parse_task_arn(task: resp)

        puts "Running database migrations for SSM"
        puts "Task ARN: #{task_arn}"

        monitoring = true
        BuildSystem.monitor_command(5) do
          resp = BuildSystem.system_return("aws ecs describe-tasks --cluster #{BuildSystem.cluster} --tasks #{task_arn}")
          resp = JSON.parse(resp)

          puts "Task Status: #{resp["tasks"].first["lastStatus"]}"

          monitoring = false if resp["tasks"].first["lastStatus"] == "STOPPED"
          monitoring
        end
      end
    end
  end

  desc "Login to ECR"
  task :login do
    puts "Logging into ECR"
    BuildSystem.system! "aws ecr get-login-password --region #{BuildSystem.aws_region} | docker login --username AWS --password-stdin #{BuildSystem.registry}"
  end
end
