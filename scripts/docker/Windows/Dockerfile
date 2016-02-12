#
# Copyright (c) .NET Foundation and contributors. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Dockerfile that creates a container suitable to build dotnet-cli on Windows

FROM windowsservercore

# This could become a "microsoft/coreclr" image, since it just installs the dependencies for CoreCLR (and stdlib)
# Install CoreCLR and CoreFx dependencies
#RUN apt-get update && \
#    apt-get -qqy install unzip curl libicu-dev libunwind8 gettext libssl-dev libcurl3-gnutls zlib1g liblttng-ust-dev lldb-3.6-dev lldb-3.6 

# Install Dotnet CLI dependencies.
# clang is required for dotnet-compile-native
#RUN apt-get -qqy install clang-3.5

# Install Build Prereqs
#RUN echo "deb http://llvm.org/apt/trusty/ llvm-toolchain-trusty-3.6 main" | tee /etc/apt/sources.list.d/llvm.list && \
#    curl http://llvm.org/apt/llvm-snapshot.gpg.key | apt-key add - && \
#    apt-get update && \
#    apt-get install -y debhelper build-essential devscripts git cmake

# Use clang as c++ compiler
#RUN update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-3.5 100
#RUN update-alternatives --set c++ /usr/bin/clang++-3.5

# Install azure cli. We need this to publish artifacts.
#RUN apt-get -y install nodejs-legacy && \
#    apt-get -y install npm && \
#    npm install -g azure-cli


#RUN apt-get install -qqy sudo

# Setup User to match Host User, and give superuser permissions
#ARG USER_ID=0
#RUN useradd -m code_executor -u ${USER_ID} -g sudo
#RUN echo 'code_executor ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# With the User Change, we need to change permssions on these directories
#RUN chmod -R a+rwx /usr/local
#RUN chmod -R a+rwx /home
#RUN chmod -R 755 /usr/lib/sudo

# Set user to the one we just created
#USER ${USER_ID}

# Install Git
RUN powershell.exe invoke-webrequest https://github.com/git-for-windows/git/releases/download/v2.7.1.windows.1/Git-2.7.1-64-bit.exe -Outfile c:\git.exe
RUN C:\git.exe /SILENT /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh"
RUN DEL C:\git.exe

# Install CMake
RUN powershell.exe invoke-webrequest https://cmake.org/files/v3.4/cmake-3.4.3-win32-x86.exe -Outfile c:\cmake.exe
RUN C:\cmake.exe /S
RUN DEL C:\cmake.exe

#Install VS 2015 Community with Update 1
RUN powershell.exe invoke-webrequest http://download.microsoft.com/download/D/2/3/D23F4D0F-BA2D-4600-8725-6CCECEA05196/vs_community_ENU.exe -Outfile c:\vs.exe
RUN powershell.exe Start-Process C:\vs.exe -ArgumentList ('/q', '/norestart', '/Full') -Wait
RUN DEL C:\vs.exe
 

ENV PATH "C:\Program Files\Git\cmd;C:\Program Files (x86)\CMake\bin"

# Set working directory
WORKDIR /opt/code



