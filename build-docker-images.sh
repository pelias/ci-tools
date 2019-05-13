#!/bin/bash
set -u

# collect params from ENV vars
DATE=`date +%Y-%m-%d`
DOCKER_REPOSITORY="pelias"
PROJECT_NAME=$CIRCLE_PROJECT_REPONAME
REVISION=$CIRCLE_SHA1

# allow docker-specific projects to be prefixed with docker in GitHub
PROJECT_NAME=${PROJECT_NAME##docker-}

# construct project name
DOCKER_PROJECT="$DOCKER_REPOSITORY/$PROJECT_NAME"

# construct valid branch name
invalid_chars="/@" # list of characters not valid in a docker tag
BRANCH="$(echo $CIRCLE_BRANCH | tr "$invalid_chars" '-')"

# list of tags to build and push
tags=(
"$DOCKER_PROJECT:$BRANCH"
"$DOCKER_PROJECT:$BRANCH-$DATE-$REVISION"
)

# additionally, push to latest tag on master branch
if [[ "$BRANCH" == "master" ]]; then
  tags+=("$DOCKER_PROJECT:latest")
fi

# build branch image and login to docker hub
docker build -t ${tags[0]} .
docker login -u="$DOCKER_USERNAME" -p="$DOCKER_PASSWORD"

# copy the image to the commit tag and push
for tag in ${tags[@]}; do
  # all tags except the first one (which was used when building)
  # must be associated with the result of docker build
  if [[ "$tag" != "${tags[0]}" ]]; then
    docker tag ${tags[0]} $tag
  fi
  docker push $tag
done
