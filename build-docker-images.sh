#!/bin/bash
set -ux

if [[ ! -f Dockerfile ]]; then
	echo "No Dockerfile found, not building"
	exit 0
fi

# fetch git tags
git fetch --depth=1 origin +refs/tags/*:refs/tags/*

# calculate basic values
DATE=`date +%Y-%m-%d`
REVISION="$(git rev-parse HEAD)"

# calculate the full repository name (org and repo name) on Circle if defined
CIRCLE_REPOSITORY="${CIRCLE_PROJECT_USERNAME:-}/${CIRCLE_PROJECT_REPONAME:-}"
# get the repository name (e.g. pelias/api) from either CircleCI or Github
DOCKER_PROJECT="${GITHUB_REPOSITORY:-$CIRCLE_REPOSITORY}"

# construct project name, removing `docker-` prefix if present
# this means a Github repository like pelias/docker-libpostal-baseimage will
# end up pushing to the pelias/libpostal-baseimage docker tag
DOCKER_PROJECT="${DOCKER_PROJECT/\/docker-/\/}"

# construct a "branch" name valid on Docker
invalid_chars="/@" # list of characters not valid in a docker tag
RAW_BRANCH="${GITHUB_REF:-$CIRCLE_BRANCH}" # get the branch from either Github or Circle
# take the actual branch name and replace invalid characters with dashes
BRANCH="$(echo $RAW_BRANCH | cut -d'/' -f 3- | tr "$invalid_chars" '-')"

# list of tags to build and push
tags=(
"$DOCKER_PROJECT:$BRANCH"
"$DOCKER_PROJECT:$BRANCH-$DATE-$REVISION"
)

# additionally, push to latest tag on master branch
if [[ "$BRANCH" == "master" ]]; then
  tags+=("$DOCKER_PROJECT:latest")
fi

# additionally, push the github version tags for the current revision when the branch is equals to master
if [[ "$BRANCH" == "master" ]]; then
  for tag in "$(git tag --points-at $REVISION)"; do
    if [[ -n "$tag" ]]; then
      tags+=("$DOCKER_PROJECT:$tag")
    fi
  done
fi

# default build targets can be configured with the DOCKER_BUILD_PLATFORMS env var
DOCKER_BUILD_DEFAULT_PLATFORMS='linux/amd64,linux/arm64'
DOCKER_BUILD_PLATFORMS=${DOCKER_BUILD_PLATFORMS:-$DOCKER_BUILD_DEFAULT_PLATFORMS}

# registry configuration
# space-separated list of registries to push to (defaults to Docker Hub if not set)
# for Docker Hub only: leave REGISTRIES unset or use "docker.io"
# for AWS ECR: export REGISTRIES="123456789012.dkr.ecr.us-east-1.amazonaws.com"
# for multiple: export REGISTRIES="docker.io 123456789012.dkr.ecr.us-east-1.amazonaws.com ghcr.io"
REGISTRIES="${REGISTRIES:-docker.io}"

# log in to all registries _before_ building to avoid rate limits
for registry in $REGISTRIES; do
  if [[ "$registry" =~ docker\.io ]]; then
    # Docker Hub login (requires: DOCKER_USERNAME, DOCKER_PASSWORD)
    docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"
  elif [[ "$registry" =~ \.ecr\. ]]; then
    # AWS ECR login (requires: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION or use IAM roles)
    aws ecr get-login-password --region $(echo "$registry" | cut -d'.' -f4) | docker login --username AWS --password-stdin "$registry"
  elif [[ "$registry" =~ ghcr\.io ]]; then
    # GitHub Container Registry login (requires: GITHUB_USERNAME, GITHUB_TOKEN)
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
  fi
done

# Build and push each tag (the built image will be reused after the first build)
for tag in ${tags[@]}; do
  # legacy single-arch builds using `docker build` are suffixed `-classic`
  # note: these are generated for backwards compatibility with older versions of
  # docker & will be deprecated/removed at a later date, please upgrade docker.
  for registry in $REGISTRIES; do
    docker build -t "$registry/$tag-classic" .
    docker push "$registry/$tag-classic"
  done

  # newer multi-arch builds using `docker buildx`
  docker buildx create --use --platform="$DOCKER_BUILD_PLATFORMS" --name 'multi-platform-builder'
  docker buildx inspect --bootstrap
  docker buildx build --push --platform="$DOCKER_BUILD_PLATFORMS" $(for registry in $REGISTRIES; do echo "-t $registry/$tag"; done) .
done
