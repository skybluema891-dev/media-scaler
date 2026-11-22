using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

// Test-only front end in an isolated copy of the bundle. Never packaged.
class EncoderFixture
{
    static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char ch in value)
        {
            if (ch == '\\') { backslashes++; continue; }
            if (ch == '"') result.Append('\\', backslashes + 1);
            result.Append('\\', backslashes).Append(ch);
            backslashes = 0;
        }
        return result.Append('\\', 2 * backslashes).Append('"').ToString();
    }
    static int Main(string[] args)
    {
        var dir = AppDomain.CurrentDomain.BaseDirectory;
        var marker = Path.Combine(dir, "fixture-mode.txt");
        var trace = Path.Combine(dir, "fixture-events.txt");
        bool converting = args.Contains("-progress");
        string mode = File.ReadAllText(marker).Trim();
        const int simulated = unchecked((int)0xC0000374);
        if (converting)
        {
            string output = args[args.Length - 1];
            bool retry = args.Contains("pools=none:frame-threads=1:wpp=0:asm=0");
            File.AppendAllText(trace, mode+" "+(retry?"retry":"initial")+" existed="+File.Exists(output)+"\r\n");
            if (!retry || mode=="repeat")
            {
                File.WriteAllText(output, "Synthetic incomplete output");
                if (mode=="cancel") Console.Read();
                return mode=="other" ? 19 : simulated;
            }
        }
        var info = new ProcessStartInfo(Path.Combine(dir, "actual-ffmpeg.exe"), string.Join(" ", args.Select(Quote))) {
            UseShellExecute=false, CreateNoWindow=true, RedirectStandardOutput=true, RedirectStandardError=true
        };
        using (var proc = Process.Start(info))
        {
            var outCopy = proc.StandardOutput.BaseStream.CopyToAsync(Console.OpenStandardOutput());
            var errCopy = proc.StandardError.BaseStream.CopyToAsync(Console.OpenStandardError());
            proc.WaitForExit();
            System.Threading.Tasks.Task.WaitAll(outCopy,errCopy);
            return proc.ExitCode;
        }
    }
}
