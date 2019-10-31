# action.build-and-push-docker

Builds a Docker image and tags it with both the commit SHA and the branch name.
Once built, the Docker imager is pushed to an ECR repository named after the git repository name.
