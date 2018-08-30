# Pelias Continuous Integration Tools

This repository is a collection of tools for running Pelias CI infrastructure.

## Current tools

### semantic-release
Install and run semantic-release, which allows us to use its functionality
without requiring it as a dev-dependency in each package.

### build-docker-images
Build docker images for a repository creating the following tags:

```
org/repo:branchname
org/repo:branchname-date-commit
```
