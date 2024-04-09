# frozen_string_literal: true

# :nodoc:

class AwsEcsTaskFactory
  attr_accessor :service, :image, :command, :task_definition, :container_definition, :task_vars, :cluster, :region

  def initialize(service:, image:, cluster:, region: "us-west-1", task_vars: [], task_definition: {}, command: [])
    @service = service
    @image = image
    @cluster = cluster
    @region = region
    @command = command
    @task_vars = task_vars

    get_task_definition(task_definition)
    get_container_definition
  end

  def get_task_definition(task_definition = {})
    # task definition parameters
    @task_definition = default_task_definition.merge(task_definition) # container parameters

    # task environment variables
    task_vars.each do |var|
      @task_definition['environment'] << parse_task_variable(var)
    end

    @task_definition['requires_compatibilities'] = %w[EC2 FARGATE]
    @task_definition['network_mode'] = "awsvpc"
    @task_definition['execution_role_arn'] = BuildSystem.ecs_task_execution_role_arn

    # ecs task family name
    # It is specific to the cluster and service
    @task_definition['family'] = "#{cluster}-#{service}".downcase.tr("-", "_")

    @task_definition
  end

  def get_container_definition
    task = [
      {
        "name" => service,
        "image" => image,
        "essential" => true,
        "portMappings" => @task_definition["port_mappings"],
        "logConfiguration" => @task_definition["logConfiguration"],
        "environment" => @task_definition["environment"],
        "ulimits" => @task_definition["ulimits"]
      }
    ]

    task[0]["command"] = command unless command.empty?

    task[0] = task[0].delete_if { |_, v| v.nil? }

    @container_definition = task.to_json
  end

  def default_task_definition
    {
      "port_mappings" => [
        {
          "containerPort" => 80
        }
      ],
      "logConfiguration" => {
        "logDriver" => "awslogs",
        "options" => {
          "awslogs-group" => cluster,
          "awslogs-region" => region,
          "awslogs-stream-prefix" => "/ecs/#{service}"
        }
      },
      "environment" => []
    }
  end

  def parse_task_variable(var)
    name, value = var.split("=")
    {
      "name" => name,
      "value" => value
    }
  end
end
