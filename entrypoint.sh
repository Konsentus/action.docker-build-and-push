#!/bin/bash -l

## Standard ENV variables provided
# ---
# GITHUB_ACTION=The name of the action
# GITHUB_ACTOR=The name of the person or app that initiated the workflow
# GITHUB_EVENT_PATH=The path of the file with the complete webhook event payload.
# GITHUB_EVENT_NAME=The name of the event that triggered the workflow
# GITHUB_REPOSITORY=The owner/repository name
# GITHUB_BASE_REF=The branch of the base repository (eg the destination branch name for a PR)
# GITHUB_HEAD_REF=The branch of the head repository (eg the source branch name for a PR)
# GITHUB_REF=The branch or tag ref that triggered the workflow
# GITHUB_SHA=The commit SHA that triggered the workflow
# GITHUB_WORKFLOW=The name of the workflow that triggerdd the action
# GITHUB_WORKSPACE=The GitHub workspace directory path. The workspace directory contains a subdirectory with a copy of your repository if your workflow uses the actions/checkout action. If you don't use the actions/checkout action, the directory will be empty

# for logging and returning data back to the workflow,
# see https://help.github.com/en/articles/development-tools-for-github-actions#logging-commands
# echo ::set-output name={name}::{value}
# -- DONT FORGET TO SET OUTPUTS IN action.yml IF RETURNING OUTPUTS

# Ensures required environment variables are supplied by workflow
check_env_vars() {
  local requiredVariables=(
    "AWS_ACCESS_KEY_ID"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_ACCOUNT_ROLE"
    "AWS_ACCOUNT_ID"
    "AWS_REGION"
  )

  for VARIABLE_NAME in "${requiredVariables[@]}"
  do
    if [[ -z "${!VARIABLE_NAME}" ]]; then
      echo "Required environment variable: ${VARIABLE_NAME} is not defined. Exiting..."
      exit 3;
    fi
  done
}

assume_role() {
  echo "Assuming role: ${AWS_ACCOUNT_ROLE} in account: ${AWS_ACCOUNT_ID}..."
  local credentials=$(aws sts assume-role --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ACCOUNT_ROLE}" --role-session-name docker-push --output json)

  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN
  export AWS_DEFAULT_REGION=${AWS_REGION}

  AWS_ACCESS_KEY_ID=$(jq -r .Credentials.AccessKeyId <<< ${credentials})
  AWS_SECRET_ACCESS_KEY=$(jq -r .Credentials.SecretAccessKey <<< ${credentials})
  AWS_SESSION_TOKEN=$(jq -r .Credentials.SessionToken <<< ${credentials})
  echo "Successfully assumed role"
}

build_docker_image() {
  echo "Building Docker image..."
  image_id=$(docker image build -q --no-cache . | cut -d':' -f2)
  echo "Successfully built Docker image"
}

tag_and_push_docker_image() {
  local image_name=$1
  local tag=$2
  echo "Tagging Docker image: ${image_name} with tag: ${tag}..."
  docker tag "${image_id}" "${image_name}:${tag}"
  echo "Pushing Docker image: ${image_name}:${tag}..."
  docker push "${image_name}:${tag}"
  echo "Successfully tagged and pushed Docker image: ${image_name}:${tag}"
}

loginToEcr() {
  echo "Logging into ECR in region: ${AWS_REGION}..."
  $(aws ecr get-login --no-include-email --region ${AWS_REGION})
  echo "Successfully logged into ECR"
}

# Exit with non zero if any of the following commands fails
set -e

check_env_vars

# Returns only repository name
# e.g. return "action.build-and-push-docker" from "Konsentus/action.build-and-push-docker"
REPOSITORY_NAME=${GITHUB_REPOSITORY##*/}

# Returns branch name
# e.g. return "master" from "refs/heads/master"
BRANCH_NAME=${GITHUB_REF##*/}

echo "Building Docker image..."

assume_role

loginToEcr

image_name="${AWS_ACCOUNT_ID}.dkr.ecr.eu-west-2.amazonaws.com/${REPOSITORY_NAME}"

# Global variable to hold the Docker image ID
image_id=""

build_docker_image

tag_and_push_docker_image $image_name $BRANCH_NAME
tag_and_push_docker_image $image_name $GITHUB_SHA

# exit with a non-zero status to flag an error/failure
