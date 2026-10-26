// SPDX-License-Identifier: MIT
// Copyright (c) 2026 FlashDragon (世界重构 / 庚辰)
using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("LocalMusicPlayer")]
[assembly: AssemblyProduct("LocalMusicPlayer")]
[assembly: AssemblyCompany("FlashDragon")]
[assembly: AssemblyCopyright("Copyright © 2026 FlashDragon (世界重构 / 庚辰)")]
[assembly: AssemblyVersion("1.0.0.1")]
[assembly: AssemblyFileVersion("1.0.0.1")]

internal static class LocalMusicPlayerHost
{
    [STAThread]
    private static void Main()
    {
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(directory, "LocalMusicPlayer.ps1");
        try
        {
            if (!File.Exists(script))
                throw new FileNotFoundException("缺少 LocalMusicPlayer.ps1，请将它与播放器放在同一目录。", script);

            Environment.CurrentDirectory = directory;
            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell powershell = PowerShell.Create())
                {
                    powershell.Runspace = runspace;
                    powershell.AddScript(File.ReadAllText(script, Encoding.UTF8));
                    powershell.Invoke();
                    if (powershell.HadErrors)
                    {
                        string details = string.Join(Environment.NewLine,
                            powershell.Streams.Error.Select(error => error.ToString()).ToArray());
                        throw new InvalidOperationException(details);
                    }
                }
            }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "LocalMusicPlayer 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
