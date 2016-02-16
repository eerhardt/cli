﻿using Microsoft.DotNet.Cli.Build.Framework;
using Microsoft.Extensions.PlatformAbstractions;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

using static Microsoft.DotNet.Cli.Build.FS;
using static Microsoft.DotNet.Cli.Build.Utils;
using static Microsoft.DotNet.Cli.Build.Framework.BuildHelpers;

namespace Microsoft.DotNet.Cli.Build
{
    public class PrepareTargets
    {
        [Target(nameof(Init), nameof(RestorePackages))]
        public static BuildTargetResult Prepare(BuildTargetContext c) => c.Success();

        // All major targets will depend on this in order to ensure variables are set up right if they are run independently
        [Target(nameof(GenerateVersions), nameof(CheckPrereqs), nameof(LocateStage0))]
        public static BuildTargetResult Init(BuildTargetContext c)
        {
            var runtimeInfo = PlatformServices.Default.Runtime;

            var configEnv = Environment.GetEnvironmentVariable("CONFIGURATION");

            if (string.IsNullOrEmpty(configEnv))
            {
                configEnv = "Debug";
            }

            c.BuildContext["Configuration"] = configEnv;

            c.Info($"Building {c.BuildContext["Configuration"]} to: {Dirs.Output}");
            c.Info("Build Environment:");
            c.Info($" Operating System: {runtimeInfo.OperatingSystem} {runtimeInfo.OperatingSystemVersion}");
            c.Info($" Platform: {runtimeInfo.OperatingSystemPlatform}");

            return c.Success();
        }

        [Target]
        public static BuildTargetResult GenerateVersions(BuildTargetContext c)
        {
            //var gitResult = Cmd("git", "rev-list", "--count", "HEAD")
            //    .CaptureStdOut()
            //    .Execute();
            //gitResult.EnsureSuccessful();
            //var commitCount = int.Parse(gitResult.StdOut);

            //gitResult = Cmd("git", "rev-parse", "HEAD")
            //    .CaptureStdOut()
            //    .Execute();
            //gitResult.EnsureSuccessful();
            //var commitHash = gitResult.StdOut.Trim();

            var branchInfo = ReadBranchInfo(c, Path.Combine(c.BuildContext.BuildDirectory, "branchinfo.txt"));
            var buildVersion = new BuildVersion()
            {
                Major = int.Parse(branchInfo["MAJOR_VERSION"]),
                Minor = int.Parse(branchInfo["MINOR_VERSION"]),
                Patch = int.Parse(branchInfo["PATCH_VERSION"]),
                ReleaseSuffix = branchInfo["RELEASE_SUFFIX"],
                CommitCount = commitCount
            };
            c.BuildContext["BuildVersion"] = buildVersion;
            c.BuildContext["CommitHash"] = "1234";// commitHash;

            c.Info($"Building Version: {buildVersion.SimpleVersion} (NuGet Packages: {buildVersion.NuGetVersion})");
            c.Info($"From Commit: {commitHash}");

            return c.Success();
        }

        [Target]
        public static BuildTargetResult LocateStage0(BuildTargetContext c)
        {
            // We should have been run in the repo root, so locate the stage 0 relative to current directory
            var stage0 = DotNetCli.Stage0.BinPath;

            if (!Directory.Exists(stage0))
            {
                return c.Failed($"Stage 0 directory does not exist: {stage0}");
            }

            // Identify the version
            var version = File.ReadAllLines(Path.Combine(stage0, "..", ".version"));
            c.Info($"Using Stage 0 Version: {version[1]}");

            return c.Success();
        }

        [Target]
        public static BuildTargetResult CheckPrereqs(BuildTargetContext c)
        {
            try
            {
                Command.Create("cmake", "--version")
                    .CaptureStdOut()
                    .CaptureStdErr()
                    .Execute();
            }
            catch (Exception ex)
            {
                string message = $@"Error running cmake: {ex.Message}
cmake is required to build the native host 'corehost'";
                if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                {
                    message += Environment.NewLine + "Download it from https://www.cmake.org";
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux))
                {
                    message += Environment.NewLine + "Ubuntu: 'sudo apt-get install cmake'";
                }
                else if (RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
                {
                    message += Environment.NewLine + "OS X w/Homebrew: 'brew install cmake'";
                }
                return c.Failed(message);
            }

            return c.Success();
        }

        [Target]
        public static BuildTargetResult CheckPackageCache(BuildTargetContext c)
        {
            var ciBuild = string.Equals(Environment.GetEnvironmentVariable("CI_BUILD"), "1", StringComparison.Ordinal);

            if (ciBuild)
            {
                // On CI, HOME is redirected under the repo, which gets deleted after every build.
                // So make NUGET_PACKAGES outside of the repo.
                var nugetPackages = Path.GetFullPath(Path.Combine(c.BuildContext.BuildDirectory, "..", ".nuget", "packages"));
                Environment.SetEnvironmentVariable("NUGET_PACKAGES", nugetPackages);
                Dirs.NuGetPackages = nugetPackages;
            }

            // Set the package cache location in NUGET_PACKAGES just to be safe
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("NUGET_PACKAGES")))
            {
                Environment.SetEnvironmentVariable("NUGET_PACKAGES", Dirs.NuGetPackages);
            }

            CleanNuGetTempCache();

            // Determine cache expiration time
            var cacheExpiration = 7 * 24; // cache expiration in hours
            var cacheExpirationStr = Environment.GetEnvironmentVariable("NUGET_PACKAGES_CACHE_TIME_LIMIT");
            if (!string.IsNullOrEmpty(cacheExpirationStr))
            {
                cacheExpiration = int.Parse(cacheExpirationStr);
            }

            if (ciBuild)
            {
                var cacheTimeFile = Path.Combine(Dirs.NuGetPackages, "packageCacheTime.txt");

                DateTime? cacheTime = null;
                try
                {
                    // Read the cache file
                    if (File.Exists(cacheTimeFile))
                    {
                        var content = File.ReadAllText(cacheTimeFile);
                        if (!string.IsNullOrEmpty(content))
                        {
                            cacheTime = DateTime.ParseExact("O", content, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal);
                        }
                    }
                }
                catch (Exception ex)
                {
                    c.Warn($"Error reading NuGet cache time file, leaving the cache alone");
                    c.Warn($"Error Detail: {ex.ToString()}");
                }

                if (cacheTime == null || (cacheTime.Value.AddHours(cacheExpiration) < DateTime.UtcNow))
                {
                    // Cache has expired or the status is unknown, clear it and write the file
                    c.Info("Clearing NuGet cache");
                    Rmdir(Dirs.NuGetPackages);
                    Mkdirp(Dirs.NuGetPackages);
                    File.WriteAllText(cacheTimeFile, DateTime.UtcNow.ToString("O"));
                }
            }

            return c.Success();
        }

        [Target(nameof(CheckPackageCache))]
        public static BuildTargetResult RestorePackages(BuildTargetContext c)
        {
            var dotnet = DotNetCli.Stage0;

            dotnet.Restore().WorkingDirectory(Path.Combine(c.BuildContext.BuildDirectory, "src")).Execute().EnsureSuccessful();
            dotnet.Restore().WorkingDirectory(Path.Combine(c.BuildContext.BuildDirectory, "tools")).Execute().EnsureSuccessful();

            return c.Success();
        }

        private static IDictionary<string, string> ReadBranchInfo(BuildTargetContext c, string path)
        {
            var lines = File.ReadAllLines(path);
            var dict = new Dictionary<string, string>();
            c.Verbose("Branch Info:");
            foreach (var line in lines)
            {
                if (!line.Trim().StartsWith("#") && !string.IsNullOrWhiteSpace(line))
                {
                    var splat = line.Split(new[] { '=' }, 2);
                    dict[splat[0]] = splat[1];
                    c.Verbose($" {splat[0]} = {splat[1]}");
                }
            }
            return dict;
        }
    }
}
