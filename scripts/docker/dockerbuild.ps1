## Copyright (c) .NET Foundation and contributors. All rights reserved.# Licensed under the MIT license. See LICENSE file in the project root for full license information.#
. "$PSScriptRoot\..\common\_common.ps1"
cd $REPOROOTsetVarIfDefault "DOTNET_BUILD_CONTAINER_TAG" "dotnetcli-build"
setVarIfDefault "DOTNET_BUILD_CONTAINER_NAME" "dotnetcli-build-container"
setVarIfDefault "DOCKER_HOST_SHARE_DIR" "$(Convert-Path .)"
setVarIfDefault "DOCKER_OS" "Windows"
setVarIfDefault "BUILD_COMMAND" "/opt/code/scripts/build/build.ps1"

# Build the docker container (will be fast if it is already built)
header "Building Docker Container"
docker build -t $DOTNET_BUILD_CONTAINER_TAG scripts/docker/$DOCKER_OS
# --build-arg USER_ID=$(id -u)

# Run the build in the container
header "Launching build in Docker Container"
info "Using code from: $DOCKER_HOST_SHARE_DIR"
docker run -t --rm --sig-proxy=true `
   --name $DOTNET_BUILD_CONTAINER_NAME `
   -v "$DOCKER_HOST_SHARE_DIR\:/opt/code" `
   -e DOTNET_CLI_VERSION `
   -e SASTOKEN `
   -e STORAGE_ACCOUNT `
   -e STORAGE_CONTAINER `
   -e CHANNEL `
   -e CONNECTION_STRING `
   -e REPO_ID `
   -e REPO_USER `
   -e REPO_PASS `
   -e REPO_SERVER `
   $DOTNET_BUILD_CONTAINER_TAG `
   powershell -c "${BUILD_COMMAND}"
