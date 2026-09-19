using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string appPath = Path.Combine(
            root,
            "app",
            "1.1.2",
            "media_scaler.exe"
        );

        if (!File.Exists(appPath))
        {
            MessageBox.Show(
                "アプリ本体が見つかりません。\nフォルダ構成を変更せずに使用してください。",
                "メディア・スケーラー",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = appPath,
            WorkingDirectory = Path.GetDirectoryName(appPath),
            UseShellExecute = true
        });
    }
}
