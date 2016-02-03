#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

param(
    # The path to the folder containing nuget.exe
    [Parameter(Mandatory=$true)][string]$NugetPath,

    # The API key to use.
    [Parameter(Mandatory=$true)][string]$ApiKey)

. "$PSScriptRoot\..\common\_common.ps1"

$Packages = Get-ChildItem –Path $env:NUGET_PACKAGES –Include *.nupkg -Recurse

$env:PATH = "$env:PATH;$NugetPath"
foreach ($Package in $Packages) {
    nuget push $Package.FullName -Source https://dotnet.myget.org/F/cli-deps/api/v2/package -ApiKey $ApiKey
}