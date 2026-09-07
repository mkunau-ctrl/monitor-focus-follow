// Native.cs - duenne Wrapper um die Windows-API fuer monitor-focus-follow.
// Enthaelt KEINE Entscheidungslogik (die steckt in FocusLogic.psm1).
// Wird zur Laufzeit per Add-Type kompiliert:
//   Add-Type -TypeDefinition (Get-Content src/Native.cs -Raw) `
//            -ReferencedAssemblies System.Windows.Forms

using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MFF
{
    public static class Native
    {
        // ----- Structs -----
        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        // ----- P/Invoke -----
        [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(POINT p);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder buf, int max);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
        [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
        [DllImport("user32.dll")] private static extern bool SystemParametersInfo(uint action, uint param, IntPtr vparam, uint winini);
        [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
        [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hwnd, int cmdShow);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
        [DllImport("shell32.dll")] private static extern int SHQueryUserNotificationState(out int state);

        // ----- Konstanten -----
        private const uint GA_ROOT = 2;
        private const int  GWL_EXSTYLE = -20;
        private const int  WS_EX_TOOLWINDOW = 0x00000080;
        private const int  WS_EX_NOACTIVATE = 0x08000000;
        private const uint SPI_SETFOREGROUNDLOCKTIMEOUT = 0x2001;
        private static readonly IntPtr HWND_TOP = IntPtr.Zero;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;
        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);
        private const int SW_HIDE = 0;

        // ----- Oeffentliche API -----

        // Mausposition in virtuellen Bildschirmkoordinaten -> {x, y}.
        public static int[] GetCursorPos()
        {
            POINT p;
            if (GetCursorPos(out p)) return new int[] { p.X, p.Y };
            return new int[] { 0, 0 };
        }

        // Oberstes (Wurzel-)Fenster unter dem Punkt.
        public static IntPtr GetRootWindowAt(int x, int y)
        {
            try
            {
                POINT p; p.X = x; p.Y = y;
                IntPtr h = WindowFromPoint(p);
                if (h == IntPtr.Zero) return IntPtr.Zero;
                IntPtr root = GetAncestor(h, GA_ROOT);
                return root != IntPtr.Zero ? root : h;
            }
            catch { return IntPtr.Zero; }
        }

        public static IntPtr GetForeground()
        {
            try { return GetForegroundWindow(); } catch { return IntPtr.Zero; }
        }

        public static string GetClassNameOf(IntPtr h)
        {
            try
            {
                var sb = new StringBuilder(256);
                int n = GetClassName(h, sb, sb.Capacity);
                return n > 0 ? sb.ToString() : "";
            }
            catch { return ""; }
        }

        // Prozessname ohne Endung, "" bei Fehler.
        public static string GetProcessNameOf(IntPtr h)
        {
            try
            {
                uint pid;
                GetWindowThreadProcessId(h, out pid);
                if (pid == 0) return "";
                using (var proc = Process.GetProcessById((int)pid))
                {
                    return proc.ProcessName;
                }
            }
            catch { return ""; }
        }

        public static bool IsVisibleTopLevel(IntPtr h)
        {
            try
            {
                if (!IsWindow(h) || !IsWindowVisible(h)) return false;
                return GetAncestor(h, GA_ROOT) == h;
            }
            catch { return false; }
        }

        // True, wenn ein Wechsel besser unterbleibt: die Shell meldet
        // Vollbild-/Praesentations-/Beschaeftigt-Zustand ODER das
        // Vordergrundfenster deckt seinen ganzen Monitor ab.
        public static bool IsForegroundFullscreen()
        {
            // 1. Offizielle Shell-Abfrage (zuverlaessig bei echten Spielen).
            try
            {
                int state;
                if (SHQueryUserNotificationState(out state) == 0)
                {
                    // 2 = QUNS_BUSY, 3 = QUNS_RUNNING_D3D_FULL_SCREEN,
                    // 4 = QUNS_PRESENTATION_MODE
                    if (state == 2 || state == 3 || state == 4) return true;
                }
            }
            catch { }

            // 2. Fallback: Fensterrechteck == Monitorrechteck.
            try
            {
                IntPtr h = GetForegroundWindow();
                if (h == IntPtr.Zero) return false;

                string cls = GetClassNameOf(h);
                if (cls == "WorkerW" || cls == "Progman" || cls == "Shell_TrayWnd") return false;

                RECT r;
                if (!GetWindowRect(h, out r)) return false;

                var screen = Screen.FromHandle(h);
                var b = screen.Bounds;
                return r.Left <= b.Left && r.Top <= b.Top && r.Right >= b.Right && r.Bottom >= b.Bottom;
            }
            catch { return false; }
        }

        // False, wenn das Fenster ein Tool-Fenster ist oder nicht aktiviert
        // werden will (WS_EX_NOACTIVATE). Bei Fehler true (nicht faelschlich
        // blockieren).
        public static bool HasAcceptableExStyle(IntPtr h)
        {
            try
            {
                int ex = GetWindowLong(h, GWL_EXSTYLE);
                if ((ex & WS_EX_TOOLWINDOW) != 0) return false;
                if ((ex & WS_EX_NOACTIVATE) != 0) return false;
                return true;
            }
            catch { return true; }
        }

        // Ist die Taste mit diesem virtuellen Code gerade gedrueckt?
        public static bool IsKeyDown(int vk)
        {
            try
            {
                short mask = unchecked((short)0x8000);
                return (GetAsyncKeyState(vk) & mask) != 0;
            }
            catch { return false; }
        }

        // Fokus setzen und dabei die Foreground-Sperre umgehen.
        public static void SetForegroundForced(IntPtr h, bool raise)
        {
            try
            {
                if (h == IntPtr.Zero || !IsWindow(h)) return;

                // Sperrzeit fuer Vordergrundwechsel auf 0 setzen.
                try { SystemParametersInfo(SPI_SETFOREGROUNDLOCKTIMEOUT, 0, IntPtr.Zero, 0); } catch { }

                IntPtr fg = GetForegroundWindow();
                uint tmpPid;
                uint targetThread = GetWindowThreadProcessId(h, out tmpPid);
                uint fgThread = (fg != IntPtr.Zero) ? GetWindowThreadProcessId(fg, out tmpPid) : 0;
                uint thisThread = GetCurrentThreadId();

                bool a1 = false, a2 = false;
                try
                {
                    if (fgThread != 0 && fgThread != thisThread) a1 = AttachThreadInput(thisThread, fgThread, true);
                    if (targetThread != 0 && targetThread != thisThread) a2 = AttachThreadInput(thisThread, targetThread, true);

                    SetForegroundWindow(h);

                    if (raise)
                    {
                        SetWindowPos(h, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
                    }
                }
                finally
                {
                    if (a1) AttachThreadInput(thisThread, fgThread, false);
                    if (a2) AttachThreadInput(thisThread, targetThread, false);
                }
            }
            catch { }
        }

        // True, solange eine der drei Haupt-Maustasten gedrueckt ist
        // (linke/rechte/mittlere). Verhindert Fokuswechsel mitten im
        // Markieren oder Ziehen. Beruecksichtigt Links-/Rechtshaender-
        // Vertauschung ueber VK_LBUTTON/VK_RBUTTON nicht - beide werden
        // sowieso geprueft.
        public static bool AnyMouseButtonDown()
        {
            try
            {
                const int VK_LBUTTON = 0x01;
                const int VK_RBUTTON = 0x02;
                const int VK_MBUTTON = 0x04;
                short mask = unchecked((short)0x8000);
                if ((GetAsyncKeyState(VK_LBUTTON) & mask) != 0) return true;
                if ((GetAsyncKeyState(VK_RBUTTON) & mask) != 0) return true;
                if ((GetAsyncKeyState(VK_MBUTTON) & mask) != 0) return true;
                return false;
            }
            catch { return false; }
        }

        // Das eigene Konsolenfenster verstecken. Beim versteckten Autostart
        // sorgt schon "powershell -WindowStyle Hidden" dafuer, dass nichts
        // sichtbar wird; dieser Aufruf ist die Absicherung fuer den Fall, dass
        // doch kurz ein Fenster auftaucht (z. B. bei manuellem Start).
        public static void HideConsoleWindow()
        {
            try
            {
                IntPtr h = GetConsoleWindow();
                if (h != IntPtr.Zero) ShowWindow(h, SW_HIDE);
            }
            catch { }
        }

        // Prozess DPI-aware machen, damit Monitorkoordinaten bei Skalierung stimmen.
        public static void MakeDpiAware()
        {
            try
            {
                if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) return;
            }
            catch { }
            try { SetProcessDPIAware(); } catch { }
        }
    }
}
