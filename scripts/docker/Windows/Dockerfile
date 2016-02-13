#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Dockerfile that creates a container suitable to build dotnet-cli on Windows

FROM windowsservercore

# Install Git
RUN powershell.exe invoke-webrequest https://github.com/git-for-windows/git/releases/download/v2.7.1.windows.1/Git-2.7.1-64-bit.exe -Outfile c:\git.exe
RUN C:\git.exe /SILENT /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"
RUN DEL C:\git.exe

# Install CMake
RUN powershell.exe invoke-webrequest https://cmake.org/files/v3.4/cmake-3.4.3-win32-x86.exe -Outfile c:\cmake.exe
RUN C:\cmake.exe /S
RUN DEL C:\cmake.exe

# Install VS 2015 Community Update 1
RUN powershell.exe invoke-webrequest http://download.microsoft.com/download/5/7/A/57A99666-126E-42FA-8E70-862EDBADD215/vs_community.exe -Outfile c:\vs.exe
RUN powershell.exe Start-Process C:\vs.exe -ArgumentList ('/q', '/norestart', '/InstallSelectableItems', 'NativeLanguageSupport_VC') -Wait
RUN DEL C:\vs.exe

# Install .NET 3.5
RUN powershell.exe invoke-webrequest https://download.microsoft.com/download/7/0/3/703455ee-a747-4cc8-bd3e-98a615c3aedb/dotNetFx35setup.exe -Outfile C:\net.exe
RUN powershell.exe Start-Process C:\net.exe -ArgumentList ('/quiet', '/norestart') -Wait
RUN DEL C:\net.exe

ENV PATH "C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Program Files\Git\cmd;C:\Program Files (x86)\CMake\bin"

# Set the NUGET_PACKAGES from the build arg
ENV NUGET_PACKAGES ${NUGET_CACHE} 

# Set working directory
WORKDIR /opt/code
