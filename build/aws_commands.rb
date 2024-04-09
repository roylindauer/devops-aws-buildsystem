# frozen_string_literal: true

# :nodoc:

module BuildSystem
  module AwsCommands
    def self.aws_env
      'AWS_PAGER=""'
    end

    def self.ecs_register_task_definition(task_definition:, container_definition:, tags:)
      cmd_str = [
        aws_env,
        "aws",
        "ecs",
        "register-task-definition",
        "--container-definitions '#{container_definition}'",
        "--family #{task_definition[:family]}",
        "--requires-compatibilities #{task_definition[:requires_compatibilities].map { |e| "'" + e + "'" }.join(" ")}",
        "--network-mode #{task_definition[:network_mode]}",
        "--execution-role-arn '#{task_definition[:execution_role_arn]}'",
        "--tags '#{tags.to_json}'"
      ].compact.join(" ")

      cmd_str += " --cpu #{task_definition[:cpu]}" if task_definition.key?(:cpu)
      cmd_str += " --memory #{task_definition[:memory]}" if task_definition.key?(:memory)

      cmd_str.chomp
    end

    def self.ecs_update_service(service:, task_definition:, cluster:)
      [
        aws_env,
        "aws",
        "ecs",
        "update-service",
        "--cluster #{cluster}",
        "--service #{service}",
        "--task-definition #{task_definition}"
      ].compact.join(" ")
    end

    def self.ecs_run_task(family:, cluster:, subnets:, security_groups:, launch_type: "FARGATE", assign_public_ip: "ENABLED")
      network_configuration = {
        "awsvpcConfiguration" => {
          "subnets" => subnets,
          "securityGroups" => security_groups,
          "assignPublicIp" => assign_public_ip
        }
      }

      [
        aws_env,
        "aws",
        "ecs",
        "run-task",
        "--cluster #{cluster}",
        "--launch-type #{launch_type}",
        "--task-definition #{family}",
        "--network-configuration '#{network_configuration.to_json}'"
      ].compact.join(" ")
    end

    def self.parse_task_revision(task:)
      task = JSON.parse(task)

      raise "Task definition not found in JSON" unless task.key?("taskDefinition")

      task["taskDefinition"]["revision"]
    rescue JSON::ParserError
      raise "Failed to parse task revision"
    end

    def self.parse_task_arn(task:)
      task = JSON.parse(task)

      raise "Tasks not found in JSON" unless task.key?("tasks")

      task["tasks"].first["taskArn"]
    rescue JSON::ParserError
      raise "Failed to parse task ARN"
    end
  end
end
