// Windows Bluetooth Fixer - tiny elevating launcher.
// Compiled with the C# compiler that ships inside every Windows install (.NET Framework 4.x),
// so there is nothing to download. It requests administrator rights through its manifest and
// starts the PowerShell GUI with no console window.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string[] candidates = {
            Path.Combine(dir, @"src\BluetoothFixer.GUI.ps1"),
            Path.Combine(dir, @"..\src\BluetoothFixer.GUI.ps1"),
            Path.Combine(dir, "BluetoothFixer.GUI.ps1")
        };
        string script = null;
        foreach (string c in candidates) { if (File.Exists(c)) { script = Path.GetFullPath(c); break; } }
        if (script == null)
        {
            MessageBox.Show("BluetoothFixer.GUI.ps1 was not found next to this program.\r\nKeep BluetoothFixer.exe in the folder that contains the 'src' folder.", "Windows Bluetooth Fixer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        string extra = args.Length > 0 ? " " + string.Join(" ", args) : " -AutoDiagnose";
        var psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"" + extra);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = Path.GetDirectoryName(script);
        try { Process.Start(psi); }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start PowerShell: " + ex.Message, "Windows Bluetooth Fixer", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        return 0;
    }
}
