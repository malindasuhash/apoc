using System;
using System.IO;

namespace FileMonitor
{
    class Monitor
    {
        static void Run(string[] args)
        {
            // The directory you want to watch
            string pathToWatch = @"C:\VS\acc-output";

            // Verify the path exists before starting the watcher
            if (!Directory.Exists(pathToWatch))
            {
                Console.WriteLine($"Directory not found: {pathToWatch}");
                return;
            }

            using (FileSystemWatcher watcher = new FileSystemWatcher())
            {
                watcher.Path = pathToWatch;

                // Watch for changes in LastAccess and LastWrite times, and
                // the renaming of files or directories.
                watcher.NotifyFilter = NotifyFilters.LastAccess
                                     | NotifyFilters.LastWrite
                                     | NotifyFilters.FileName
                                     | NotifyFilters.DirectoryName;

                // Only watch text files. Use "*.*" to watch all files.
                watcher.Filter = "*.*";

                // Add event handlers.
                watcher.Changed += OnChanged;
                watcher.Created += OnCreated;
                watcher.Deleted += OnDeleted;
                watcher.Renamed += OnRenamed;
                watcher.Error   += OnError;

                // Begin watching.
                watcher.EnableRaisingEvents = true;
                
                // Monitor subdirectories as well
                watcher.IncludeSubdirectories = true;

                Console.WriteLine($"Listening for changes in {pathToWatch}...");
                Console.WriteLine("Press 'q' to quit the sample.");
                
                while (Console.Read() != 'q') ;
            }
        }

        // Define the event handlers.
        private static void OnChanged(object sender, FileSystemEventArgs e)
        {
            if (e.ChangeType != WatcherChangeTypes.Changed)
            {
                return;
            }
            Console.WriteLine($"Changed: {e.FullPath}");
        }

        private static void OnCreated(object sender, FileSystemEventArgs e)
        {
            Console.WriteLine($"Created: {e.FullPath}");
        }

        private static void OnDeleted(object sender, FileSystemEventArgs e)
        {
            Console.WriteLine($"Deleted: {e.FullPath}");
        }

        private static void OnRenamed(object sender, RenamedEventArgs e)
        {
            Console.WriteLine($"Renamed:");
            Console.WriteLine($"    Old: {e.OldFullPath}");
            Console.WriteLine($"    New: {e.FullPath}");
        }

        private static void OnError(object sender, ErrorEventArgs e)
        {
            PrintException(e.GetException());
        }

        private static void PrintException(Exception? ex)
        {
            if (ex != null)
            {
                Console.WriteLine($"Message: {ex.Message}");
                Console.WriteLine("Stacktrace:");
                Console.WriteLine(ex.StackTrace);
                PrintException(ex.InnerException);
            }
        }
    }
}