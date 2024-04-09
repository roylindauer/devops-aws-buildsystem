# frozen_string_literal: true

# :nodoc:

require 'pathname'
require 'yaml'
require 'erb'
require 'logger'
require 'English'

require_relative "aws_commands"
require_relative "aws_task_factory"

module BuildSystem
  attr_accessor :root_dir, :build_dir, :build_file, :build_num, :branch

  # Returns true if the current environment is a CI environment
  def self.is_ci?
    ENV.key?('CI')
  end

  # Returns true if the current environment is a dry run
  def self.dry_run?
    ENV.key?('DRY_RUN')
  end

  # Executes a system command, logging the command
  def self.system(*argv)
    log_system_command(*argv)
    Kernel.system(*argv)
  end

  # Executes a system command, logging the command, and raising an exception if the command fails
  def self.system!(*argv)
    return true if self.system(*argv)

    raise "`#{$CHILD_STATUS.exitstatus}` was returned"
  end

  # Executes a system command, logging the command, and returning the output
  def self.system_return(cmd)
    log_system_command(cmd)
    `#{cmd}`
  end

  # Logger
  def self.logger
    @logger ||= ::Logger.new(STDOUT)
  end

  # Root directory of the project
  def self.root_dir
    @root_dir ||= find_root_dir
  end

  # Build directory of the project
  def self.build_dir
    @build_dir ||= File.join(root_dir, 'build')
  end

  # Build file of the project
  def self.build_file
    @build_file ||= File.join(root_dir, 'build.yml')
  end

  # Find the root directory of the project
  def self.find_root_dir
    root_directory = Pathname(Dir.home)
    starting_directory = Pathname(Dir.pwd)

    current_directory = starting_directory
    while(current_directory != root_directory)
      break if File.exist?("#{current_directory}/build.yml")

      current_directory = current_directory.dirname
    end

    if current_directory == root_directory
      logger.error "Couldn't find build.yml in any parent directory. Are you sure you're in the right directory"
      exit(1)
    end

    current_directory
  end

  # Given an object, return a string that can be used as a command line argument
  # ie: {foo: 'bar', baz: 'qux'} => '--flag foo=bar --flag baz=qux'
  # Useful for building docker build args, ie: --build-arg foo=bar --build-arg baz=qux
  # Or for building docker run args, ie: --env foo=bar --env baz=qux
  def self.convert_object_to_arg(flag:, args: {})
    return '' if args.empty?
    args = convert_object_to_args(args)
    "#{flag} " + args.join(" #{flag} ") if args
  end

  # Given an object, return an array of strings that can be used as a command line argument
  def self.convert_object_to_args(obj)
    obj&.map{|k, v| [k,v] * '='}
  end

  # Returns the projects defined in the build.yml file
  def self.projects
    BUILD_CONFIG[:projects]
  end

  # Returns the encryption key
  def self.enc_key
    ENV["ENC_KEY"]
  end

  # Returns the branch
  def self.branch
    @branch ||= fetch_branch
  end

  # Fetches the branch from the environment
  def self.fetch_branch
    return ENV["GITHUB_REF_NAME"].split("/")[0] if ENV["GITHUB_REF_NAME"]
    return `git rev-parse --abbrev-ref HEAD`.chomp
    # return ENV['CIRCLE_TAG'].split('-').first if ENV.key?('CIRCLE_TAG')

    # ENV['CIRCLE_BRANCH']
  end

  def self.git_ref
    branch
  end

  def self.build_num
    @build_num ||= fetch_build_num
  end

  # Fetches the build number from the environment
  def self.fetch_build_num
    ENV["GITHUB_RUN_ID"] || "1"
  end

  # Returns the short hash of the current commit
  def self.short_hash(commit: false, length: 10)
    hash = commit || 'HEAD'
    system_return "git rev-parse --short=#{length} #{hash}".chomp
  end

  # Clusters defined in the build.yml file
  def self.clusters(project = nil)
    return BUILD_CONFIG[:projects][project][:clusters] if project && BUILD_CONFIG[:projects][project][:clusters]
    BUILD_CONFIG[:clusters] || {
      develop: "DEVELOP",
      staging: "STAGING",
      production: "PRODUCTION"
    }
  end

  # Returns the cluster for the current branch
  def self.cluster
    clusters[branch.to_sym]
  end

  # Returns true if the current branch has a cluster defined
  def self.cluster?
    clusters.key? branch.to_sym
  end

  # Returns the docker tag
  def self.docker_tag
    build_num || 'latest'
  end

  # Returns the docker image uri
  def self.docker_image_uri(image)
    "#{BUILD_CONFIG[:deploy][:registry]}/#{image}"
  end

  # Returns the docker image uri with the tag
  def self.docker_image(image)
    "#{docker_image_uri(image)}:#{docker_tag}"
  end

  # Environment variables to pass to the Docker run command
  def self.docker_run_environment(project, service)
    self.convert_object_to_arg(flag: '--env', args: task_environment(project, service))
  end

  # Logs a system command
  def self.log_system_command(*argv)
    BuildSystem::CommandLogger.write(*argv)
  end


  def self.default_task_environment
    %W[ENV=#{cluster} ENC_KEY=#{enc_key} BUILD_NUM=#{build_num} DEPLOY_ENV=#{cluster}]
  end

  def self.task_environment(project_config = {})
    te = project_config[:task_environment]&.map { |k, v| [k, v].join "=" } || []
    te += default_task_environment
    te
  end

  def self.task_tags
    [
      {
        "key" => "git_ref",
        "value" => git_ref
      },
      {
        "key" => "build",
        "value" => build_num
      }
    ]
  end

  def self.task_definition(project_config = {})
    # Find task definition in build.yml
    if project_config.dig(:task_definition)
      return project_config[:task_definition][git_ref.downcase.to_sym] if project_config[:task_definition].key?(git_ref.downcase.to_sym)
      return project_config[:task_definition][:default] if project_config[:task_definition].key?(:default)
    end

    # Default task definition
    {
      cpu: 256,
      memory: 1024
    }
  end

  def self.valid_json?(value)
    result = JSON.parse(value)
    result.is_a?(Hash) || result.is_a?(Array)
  rescue JSON::ParserError, TypeError
    false
  end

  def self.monitor_command(timeout = 5, &block)
    while yield
      sleep(timeout)
    end
  end

  def self.ecs_task_execution_role_arn
    BUILD_CONFIG[:deploy][:ecs_task_execution_role_arn] || "arn:aws:iam::#{aws_account_id}:role/ecsTaskExecutionRole"
  end

  def self.aws_region
    BUILD_CONFIG[:deploy][:aws_region] || "us-west-1"
  end

  def self.subnets
    BUILD_CONFIG[:deploy][:subnets] || []
  end

  def self.security_groups
    BUILD_CONFIG[:deploy][:security_groups] || []
  end

  def self.registry
    BUILD_CONFIG[:deploy][:registry] || "public.ecr.aws"
  end

  # A logger for system commands
  module CommandLogger
    @@log = []
    def self.log
      @@log
    end

    def self.write(command)
      @@log << command
    end

    def self.out
      if @@log.length > 0
        puts "-" * 80
        BuildSystem.logger.info "Command Log:"
        @@log.each do |command|
          BuildSystem.logger.info("$ #{command}")
        end
        puts "-" * 80
      end
    end
  end

end
