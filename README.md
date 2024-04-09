# Buildsystem

This a smaller scale version of a buildsystem I developed while at Blackbird Logistics to build, test, deploy a monorepo of docker based projects to AWS ES Fargate clusters, AWS CloudFront distributions, and some one-off services on some internal VMs. Additionally it was responsible for building and pushing base images upon which many services in the monorepo depended.

The ultimate goal was to provide tooling that enabled a developer to clone the monorepo, run a single setup command, and be off and running. The only dependencies are system Ruby and Docker. System ruby so there are no 3rd party dependencies to the build system. We mostly achieved that, and more, using this project as the basic framework. 

The tool is exposed as Rake tasks and was designed to be used by developers to build and run projects locally, but also for CI to automate the build, test, and deployment of Docker images. 

A build.yml file describes the monorepo and informs the Rake tasks on which tasks to generate. In the work at Blackbird I developed helpers for running docker compose and ensuring proper service startup ordering and automatic building of base images for local services. 

It was a fun system to write to solve some of the many challenges in working in a monorepo. 
