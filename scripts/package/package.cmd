@echo off

REM Copyright (c) .NET Foundation and contributors. All rights reserved.
REM Licensed under the MIT license. See LICENSE file in the project root for full license information.

set PackageDir="%~dp0..\..\artifacts\packages\dnvm"

powershell -NoProfile -NoLogo -Command "%~dp0package.ps1 %*; exit $LastExitCode;"
