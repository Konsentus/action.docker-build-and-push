# Docker Build, Tag and Push to AWS ECR

This action will build, tag and push a Docker image to an AWS ECR repository.

`Docker build` will attempt to build from a Dockerfile located in the root of your repository.

The branch name and commit SHA are added as tags.

By default, the newly built image is pushed to an AWS ECR repository with the same name as your Github repository.

See [Optional Arguments](#optional-arguments) for information on adding additional tags and overriding the AWS ECR repository name.

## Usage

### Example Pipeline

```yaml
name: Build and Push Docker Image
on:
  push:
    branches:
      - "master"
jobs:
  build-and-push:
    env:
      AWS_REGION: eu-west-2
      AWS_ACCOUNT_ROLE: deploy
      AWS_ACCOUNT_ID: ${{ secrets.ECR_AWS_ACCOUNT_ID }}
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@master
      - name: Build and Push
        uses: konsentus/action.build-and-push-image@master
        with:
          ecr_repository_name: "my-ecr-repository"
          additional_tags: "built-with-Github-Actions, another-tag"
```

## Environment Variables

- `AWS_REGION`: The region in which the ECR repository exists.
- `AWS_ACCOUNT_ROLE`: The name of a IAM Role that has the [required permissions](#Role-permissions) to push to the AWS ECR repository.
- `AWS_ACCOUNT_ID`: The account number of the AWS account in which the ECR repository exists.
- `AWS_ACCESS_KEY_ID`: The AWS Access Key ID of a user with permission to assume the **AWS_ACCOUNT_ROLE**.
- `AWS_SECRET_ACCESS_KEY`: The AWS Secret Access Key that pairs with the `AWS_ACCESS_KEY_ID`.

**Suggestion**: Store your AWS account details in [Secrets](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets)

## Optional Arguments

- `ecr_repository_name`: By default this action will attempt to push the Docker image to an AWS ECR repository named after the Github repository name (minus the repository owner). This argument allows the sepcifying of an alternative AWS ECR repository name.
- `additional_tags`: A comma separated list of tags to apply to the image, in addition to the default tags. These values will be stripped on whitespace before being applied.

## Outputs

- `old_image_digest`: In the case that a Docker image tagged with the branch name already exists in the AWS ECR repository, this output variable will hold the value of the Docker image digest. If there are no Docker images tagged with the branch name, then this will be empty.
- `new_image_digest`: This output variable will hold the Docker image digest of the newly built image.

## Role permissions

This action uses [AWS Security Token Service](https://docs.aws.amazon.com/STS/latest/APIReference/Welcome.html) to to assume the **AWS_ACCOUNT_ROLE**.

The following shows an example policy containing the permissions that are required for the **AWS_ACCOUNT_ROLE** to perform the AWS commands contained in the action.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:TagResource",
        "ecr:PutImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```

## Future Enhancements

- Allow the passing of an optional argument to specify the location of the Dockerfile to build.
- Tag master branch with 'latest' by default.
