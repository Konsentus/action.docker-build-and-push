# Docker Build, Tag and Push

This action will build, tag and push a Docker image to an AWS ECR repository.

## Usage

## Example Pipeline

```yaml
name: Build and Push Docker Image
on:
  push:
    branches:
      - 'master'
jobs:
  build-and-push:
    env:
      AWS_ACCOUNT_ID: ${{ secrets.ECR_AWS_ACCOUNT_ID }}
      AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      AWS_REGION: eu-west-2
      AWS_ACCOUNT_ROLE: deploy
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@master
      - name: Build and Push
        uses: konsentus/action.build-and-push-image@master
        with:
          additional_tags: 'built-with-Github-Actions, another-tag'
          ecr_repository_name: 'my-ecr-repository'
```
