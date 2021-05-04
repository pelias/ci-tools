#!/bin/bash
set -ux

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
BRANCH="$(echo $RAW_BRANCH | cut -d'/' -f 3 | tr "$invalid_chars" '-')"

# list of tags to build and push
tags=(
"$DOCKER_PROJECT:$BRANCH"
"$DOCKER_PROJECT:$BRANCH-$DATE-$REVISION"
)

# additionally, push to latest tag on master branch
if [[ "$BRANCH" == "master" ]]; then
  tags+=("$DOCKER_PROJECT:latest")
fi

# log in to Docker Hub _before_ building to avoid rate limits
docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

# Build and push each tag (the built image will be reused after the first build)
for tag in ${tags[@]}; do
  docker build -t $tag .
  docker push $tag
done
