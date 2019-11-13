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
      echo "Required environment variable: ${VARIABLE_NAME} is not defined" >&2
      return 3
    fi
  done
}

# Assume a role in AWS using AWS STS
assume_role() {
  echo "Assuming role: ${AWS_ACCOUNT_ROLE} in account: ${AWS_ACCOUNT_ID}"

  local credentials

  credentials=$(aws sts assume-role --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ACCOUNT_ROLE}" --role-session-name docker-build-and-push --output json)

  if [ $? -ne 0 ]; then
    echo "Failed to assume role ${AWS_ACCOUNT_ROLE} in account: ${AWS_ACCOUNT_ID}" >&2
    return 3
  fi

  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN
  export AWS_DEFAULT_REGION=${AWS_REGION}

  AWS_ACCESS_KEY_ID=$(jq -r .Credentials.AccessKeyId <<< ${credentials})
  AWS_SECRET_ACCESS_KEY=$(jq -r .Credentials.SecretAccessKey <<< ${credentials})
  AWS_SESSION_TOKEN=$(jq -r .Credentials.SessionToken <<< ${credentials})

  echo "Successfully assumed role"
}

# Request ECR credentials and execute returned command to login
login_to_ecr() {
  echo "Logging into ECR in region: ${AWS_REGION}"
  $(aws ecr get-login --no-include-email --region ${AWS_REGION})

  if [ $? -ne 0 ]; then
    echo "Failed to log into AWS ECR" >&2
    return 3
  fi

  echo "Successfully logged into ECR"
}

# Build Docker image
build_docker_image() {
  echo "Building Docker image"
  docker image build -t "${ecr_repository_name}" .

  if [ $? -ne 0 ]; then
    echo "Failed to build Docker image" >&2
    return 3
  fi

  echo "Successfully built Docker image"
}

# Tags the image and pushed to AWS ECR
tag_and_push_docker_image() {
  local tag=$1

  echo "Tagging Docker image: ${image_id} with ${image_name}:${tag}"
  docker tag "${image_id}" "${image_name}:${tag}"

  if [ $? -ne 0 ]; then
    echo "Failed to tag Docker image" >&2
    return 3
  fi

  echo "Pushing Docker image: ${image_name}:${tag}"
  docker push "${image_name}:${tag}"

  if [ $? -ne 0 ]; then
    echo "Failed to push Docker image" >&2
    return 3
  fi

  echo "Successfully tagged and pushed Docker image: ${image_name}:${tag}"
}

# Retrieve an image digest from AWS ECR
get_docker_image_digest() {
  local image_digest_result
  image_digest_result=$(aws ecr describe-images --repository-name ${ecr_repository_name} --image-ids imageTag=$1 --query 'imageDetails[0].imageDigest' --output text 2>&1)
  if [ $? -ne 0 ]; then
    echo ${image_digest_result} >&2
    if [[ ${image_digest_result} =~ "(ImageNotFoundException)" ]]; then
      return 0
    else
      return 3
    fi
  else
    echo ${image_digest_result}
    return 0
  fi
}

check_env_vars || exit $?

additional_tags=()

# Split and strip whitespace from comma separated values into an array
if ! [ -z "${INPUT_ADDITIONAL_TAGS}" ]; then
  IFS=',' read -ra additional_tags <<< "$(echo -e "${INPUT_ADDITIONAL_TAGS}" | tr -d '[:space:]')"
fi

# No ECR repository specified, fall back to Github repository name
# Returns only repository name
# e.g. return "action.build-and-push-docker" from "Konsentus/action.build-and-push-docker"
repository_name=${GITHUB_REPOSITORY##*/}
ecr_repository_name=${INPUT_ECR_REPOSITORY_NAME:-${repository_name}} # test me

# Returns branch name
# e.g. return "master" from "refs/heads/master"
branch_name=${GITHUB_REF##*/}

# Assume role with permission to login to ECR
assume_role || exit $?

# Execute inline login to AWS ECR
login_to_ecr || exit $?

# Get the Docker image digest of the previous image tagged with the same Git branch name.
# Will output warning to stderr if no images were found but still return 0.
# Any other error will exit the script here
old_image_digest=$(get_docker_image_digest ${branch_name}) || exit $?

# Output the Docker image digest
echo "::set-output name=old_image_digest::${old_image_digest}"

# Build the URI for the AWS ECR
image_name="${AWS_ACCOUNT_ID}.dkr.ecr.eu-west-2.amazonaws.com/${ecr_repository_name}"

# Build Docker image from Dockerfile in root of repository
build_docker_image || exit $?

# Retrieve image ID of Docker image
image_id=$(docker images -q "${ecr_repository_name}")

# Check if Docker found our image locally
if [ -z "${image_id}" ]; then
  echo "Failed to retrieve Docker image ID: Expected to find a local Docker image named ${ecr_repository_name}" >&2
  exit 3
fi

# Tag image with commit SHA
tag_and_push_docker_image ${GITHUB_SHA} || exit $?

# Get the Docker image digest of the image tagged with the current Git commit SHA
new_image_digest=$(get_docker_image_digest ${GITHUB_SHA})

# Exit if we are unable to find the image we just pushed
if [ -z "${new_image_digest}" ]; then
  echo "Failed to retrieve Docker image digest for new Docker image" >&2
  exit 3
fi

# Output the Docker image digest
echo "::set-output name=new_image_digest::${new_image_digest}"

# Tag image with branch name
tag_and_push_docker_image ${branch_name} || exit $?

# Add additonal tags to Docker image
for tag in "${additional_tags[@]}"
do
  tag_and_push_docker_image ${tag} || exit $?
done
