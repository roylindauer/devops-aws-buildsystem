require 'json'
require 'minitest/autorun'

require_relative '../helpers'
require_relative '../../aws_task_factory'

BUILD_CONFIG = {
    deploy: {
        repository: 'buildsystem',
        registry: '123456789012.dkr.ecr.us-west-1.amazonaws.com',
        ecs_task_execution_role_arn: 'arn:aws:iam::123456789012:role/ecsTaskExecutionRole',
        aws_region: 'us-west-1',
        subnets: [],
        security_groups: [],
        clusters: {
            develop: 'DEVELOP',
            prod: 'PROD'
        }

    },
    
    projects: {
        connect: {
            docker_build_args: {},
            image: 'connect',
            docker_tasks: {
                connect_web: {
                    task_definition: {
                        default: {cpu: 512, memory: 1024},
                    },
                    task_environment: {
                        ENABLE_WEB: 1,
                        ENABLE_CRON: 1,
                        RAILS_MAX_THREADS: 8,
                        WORKER_QUEUE: '@web'
                    }
                }
            }
        }
    }
}

class TestAwsEcsTaskFactory < Minitest::Test

  def test_get_task_definition
    service = 'connect'
    image = '123456789012.dkr.ecr.us-west-1.amazonaws.com/develop-buildsystem-connect:233'
    cluster = 'develop-buildsystem'
    region = 'us-west-1'

    expected = {
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
        "environment" => [],
        "requires_compatibilities" => ["EC2", "FARGATE"],
        "network_mode" => "awsvpc",
        "execution_role_arn" => "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
        "family" => "develop_buildsystem_connect"
    }

    task = AwsEcsTaskFactory.new(
        service: service,
        image: image,
        cluster: cluster,
        region: region
    )

    assert_equal(expected, task.task_definition)
  end

  def test_task_vars
    service = 'connect'
    image = '123456789012.dkr.ecr.us-west-1.amazonaws.com/develop-buildsystem-connect:233'
    cluster = 'develop-buildsystem'
    region = 'us-west-1'

    task = AwsEcsTaskFactory.new(
        service: service,
        image: image,
        cluster: cluster,
        region: region,
        task_vars: ['TESTVAR1=testval1', 'TESTVAR2=testval2']
    ).task_definition

    expected = [{ 'name' => 'TESTVAR1', 'value' => 'testval1' }, { 'name' => 'TESTVAR2', 'value' => 'testval2' }]

    assert_equal(expected, task['environment'])
  end

  def test_task_definition
    service = 'connect'
    image = '123456789012.dkr.ecr.us-west-1.amazonaws.com/develop-buildsystem-connect:233'
    cluster = 'develop-buildsystem'
    region = 'us-west-1'

    task = AwsEcsTaskFactory.new(
        service: service,
        image: image,
        cluster: cluster,
        region: region,
        task_definition: { 'cpu' => 2048, 'memory' => 4096 }
    ).task_definition

    assert_equal(2048, task['cpu'])
    assert_equal(4096, task['memory'])
  end

  def test_task_container_definitions
    service = 'connect'
    image = '123456789012.dkr.ecr.us-west-1.amazonaws.com/develop-buildsystem-connect:233'
    cluster = 'develop-buildsystem'
    region = 'us-west-1'

    task = AwsEcsTaskFactory.new(
        service: service,
        image: image,
        cluster: cluster,
        region: region,
        task_definition: { 'cpu' => 2048, 'memory' => 4096 }
    )

    assert_match(/"image":"123456789012.dkr.ecr.us-west-1.amazonaws.com\/develop-buildsystem-connect:233"/, task.container_definition)
    assert_match(/"name":"connect"/, task.container_definition)
    assert_match(/"portMappings":\[\{"containerPort":80}\]/, task.container_definition)
    assert_match(/"logConfiguration":\{"logDriver":"awslogs","options":\{"awslogs-group":"develop-buildsystem","awslogs-region":"us-west-1","awslogs-stream-prefix":"\/ecs\/connect"\}\}/, task.container_definition)
  end

  def test_task_container_definitions_is_escaped_json
    service = 'connect'
    image = '123456789012.dkr.ecr.us-west-1.amazonaws.com/develop-buildsystem-connect:233'
    cluster = 'develop-buildsystem'
    region = 'us-west-1'

    task = AwsEcsTaskFactory.new(
        service: service,
        image: image,
        cluster: cluster,
        region: region,
        task_definition: { 'cpu' => 2048, 'memory' => 4096 }
    )

    assert_instance_of(String, task.container_definition)
    assert(JSON.parse(task.container_definition))
  end
end
