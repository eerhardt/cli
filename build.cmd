@echo off

REM Copyright (c) .NET Foundation and contributors. All rights reserved.
REM Licensed under the MIT license. See LICENSE file in the project root for full license information.

REM Crossgen Workaround
set ComPlus_ReadyToRun=0

IF DEFINED CI_BUILD (
	set scriptFile=docker\dockerbuild.ps1
) ELSE (
	set scriptFile=run-build.ps1
)

powershell -NoProfile -NoLogo -Command "%~dp0scripts\%scriptFile% %*; exit $LastExitCode;"
