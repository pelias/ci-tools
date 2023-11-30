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

# log in to Docker Hub _before_ building to avoid rate limits
docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

# Build and push each tag (the built image will be reused after the first build)
for tag in ${tags[@]}; do
  if [ "$DOCKER_BUILD_PLATFORMS" == "classic" ]; then
    docker build -t $tag .
    docker push $tag
  else
    docker buildx create --use --platform="$DOCKER_BUILD_PLATFORMS" --name 'multi-platform-builder'
    docker buildx inspect --bootstrap
    docker buildx build --push --platform="$DOCKER_BUILD_PLATFORMS" -t $tag .
  fi
done
