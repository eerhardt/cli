using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Dnx.Runtime.Common.CommandLine;
using NuGet.Configuration;
using NuGet.Logging;
using NuGet.Protocol.Core.Types;
using NuGet.Protocol.Core.v3;

namespace PackageMirrorer
{
    internal class Program
    {
        private const string HelpOption = "-h|--help";

        public static int Main(string[] args)
        {
            var app = new CommandLineApplication()
            {
                Name = "package-mirrorer",
                FullName = "NuGet package mirrorer",
                Description = "Mirrors NuGet packages from one set of feeds into a mirror feed",
            };

            app.HelpOption(HelpOption);

            app.Command("go", go =>
            {
                go.HelpOption(HelpOption);

                var outputDir = go.Argument(
                     "[outputDir]",
                     "The local directory where the packages will be downloaded to.");

                go.OnExecute(() => MirrorPackages(outputDir.Value));
            });

            app.OnExecute(() =>
             {
                 app.ShowHelp();
                 return 0;
             });

            var exitCode = 0;

            try
            {
                exitCode = app.Execute(args);
            }
            catch (Exception e)
            {
                Console.WriteLine(e);

                exitCode = 1;
            }

            return exitCode;
        }

        private static int MirrorPackages(string outputDir)
        {
            if (string.IsNullOrEmpty(outputDir))
            {
                Console.WriteLine("Error: No outputDir specified");
                return 1;
            }

            // TODO: take in a .txt file that has these each on a line
            var feedInfo = new[]
            {
                new { Url = "https://www.myget.org/F/dotnet-core-rel/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/nugetbuild/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/aspnetcidev/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/roslyn-nightly/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/dotnet-corefxlab/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/netcore-package-prototyping/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/dotnet/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/dotnet-buildtools/api/v3/index.json" },
                new { Url = "https://www.myget.org/F/fsharp-daily/api/v3/index.json" },
            };

            List<Task> tasks = new List<Task>();
            foreach (var item in feedInfo)
            {
                tasks.Add(CloneFeed(item.Url, outputDir));
            }

            Task.WaitAll(tasks.ToArray());

            return 0;
        }

        private static async Task CloneFeed(string v3FeedUrl, string outputDir)
        {
            PackageSource packageSource = new PackageSource(v3FeedUrl);
            SourceRepository repo = new SourceRepository(packageSource, Repository.Provider.GetCoreV3());

            SearchLatestResource searchLatest = await repo.GetResourceAsync<SearchLatestResource>();

            bool more = true;
            int currentIndex = 0;
            const int pageSize = 500;

            List<ServerPackageMetadata> packages = new List<ServerPackageMetadata>();
            while (more)
            {
                more = false;

                IEnumerable<ServerPackageMetadata> packagesPage = await searchLatest.Search("", new SearchFilter(Enumerable.Empty<string>(), includePrerelease: true, includeDelisted: false), skip: currentIndex, take: pageSize, cancellationToken: CancellationToken.None);
                foreach (ServerPackageMetadata package in packagesPage)
                {
                    more = true;

                    packages.Add(package);
                }

                currentIndex += pageSize;
            }

            await DownloadPackages(repo, packages, outputDir);
        }

        private static async Task DownloadPackages(SourceRepository repo, List<ServerPackageMetadata> packages, string outputDir)
        {
            Directory.CreateDirectory(outputDir);
            ISettings settings = Settings.LoadDefaultSettings(AppContext.BaseDirectory, configFileName: null, machineWideSettings: null);
            DownloadResource downloadResource = await repo.GetResourceAsync<DownloadResource>();

            var queue = new ConcurrentQueue<ServerPackageMetadata>(packages);
            var tasks = new Task[8];
            for (var i = 0; i < tasks.Length; i++)
            {
                tasks[i] = Task.Run(async () =>
                {
                    ServerPackageMetadata package;
                    while (queue.TryDequeue(out package))
                    {
                        Console.WriteLine($"Downloading {package}...");

                        var packagePath = Path.Combine(outputDir, package.Id + "." + package.Version + ".nupkg");

                        var retryCount = 3;
                        while (retryCount-- >= 0)
                        {
                            try
                            {
                                DownloadResourceResult downloadResult = await downloadResource.GetDownloadResourceResultAsync(
                                        package, 
                                        settings, 
                                        new NullLogger(), 
                                        CancellationToken.None);

                                using (var stream = downloadResult.PackageStream)
                                using (var fileStream = File.OpenWrite(packagePath))
                                {
                                    await stream.CopyToAsync(fileStream);
                                }

                                break;
                            }
                            catch
                            {
                                // Retry
                                Console.WriteLine($"Retrying {(3 - retryCount)}...");
                            }
                        }

                        Console.WriteLine($"Downloaded {package}");
                    }
                });
            }

            await Task.WhenAll(tasks);
        }
    }
}

