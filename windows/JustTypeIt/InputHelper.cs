// Just Type It for Windows – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-type-it

using System.Runtime.InteropServices;

namespace JustTypeIt;

/// Safe keyboard and clipboard helpers shared by live checking, Quick Check and Rewrite.
static class InputHelper
{
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    const int VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_LWIN = 0x5B, VK_RWIN = 0x5C;

    /// Hotkeys fire while Ctrl+Alt are still held; sending Ctrl+C then would arrive as Ctrl+Alt+C
    /// (which types "©" in Word). Wait until every modifier and the hotkey letter are released.
    public static async Task<bool> WaitForKeysReleased(Keys? hotkeyLetter = null, int timeoutMs = 1500)
    {
        var keys = new List<int> { VK_SHIFT, VK_CONTROL, VK_MENU, VK_LWIN, VK_RWIN };
        if (hotkeyLetter is { } k) keys.Add((int)k);
        var waited = 0;
        while (keys.Any(v => (GetAsyncKeyState(v) & 0x8000) != 0))
        {
            if (waited >= timeoutMs) return false;
            await Task.Delay(20);
            waited += 20;
        }
        return true;
    }

    public static uint ForegroundProcessId()
    {
        GetWindowThreadProcessId(GetForegroundWindow(), out var pid);
        return pid;
    }

    /// A real copy of every clipboard format (GetDataObject returns a live, invalidating proxy).
    public static DataObject? SaveClipboard()
    {
        try
        {
            var src = Clipboard.GetDataObject();
            if (src == null) return null;
            var copy = new DataObject();
            foreach (var f in src.GetFormats(false))
                try { var d = src.GetData(f, false); if (d != null) copy.SetData(f, d); } catch { }
            return copy;
        }
        catch { return null; }
    }

    public static void RestoreClipboard(DataObject? saved)
    {
        try
        {
            if (saved != null && saved.GetFormats().Length > 0) Clipboard.SetDataObject(saved, true);
            else Clipboard.Clear();
        }
        catch { }
    }

    /// Copies the current selection in the foreground app and restores the clipboard. Empty if nothing is selected.
    public static async Task<string> CopySelection(Keys hotkeyLetter)
    {
        await WaitForKeysReleased(hotkeyLetter);
        var saved = SaveClipboard();
        try { Clipboard.Clear(); } catch { }
        SendKeys.SendWait("^c");
        string text = "";
        for (int i = 0; i < 40 && text.Length == 0; i++)
        {
            await Task.Delay(25);
            try { if (Clipboard.ContainsText()) text = Clipboard.GetText(); } catch { }
        }
        RestoreClipboard(saved);
        return text;
    }

    /// Pastes text over the current selection, waits until the app has read it, then restores the clipboard.
    /// `verify` (optional) returns true once the paste is visible in the target; the clipboard is restored
    /// only after that (or a timeout), so a slow app never pastes the user's old clipboard.
    public static async Task Paste(string text, Func<Task<bool>>? verify = null, bool restore = true)
    {
        var saved = restore ? SaveClipboard() : null;
        try
        {
            if (text.Length == 0) SendKeys.SendWait("{DEL}");
            else { Clipboard.SetText(text.Replace("\r\n", "\n").Replace("\n", "\r\n")); SendKeys.SendWait("^v"); }
        }
        catch { }
        if (verify != null)
            for (int i = 0; i < 30 && !await verify(); i++) await Task.Delay(50);
        else
            await Task.Delay(700);
        if (restore) RestoreClipboard(saved);
    }
}
