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
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        // ----- Konstanten -----
        private const uint GA_ROOT = 2;
        private const uint SPI_SETFOREGROUNDLOCKTIMEOUT = 0x2001;
        private static readonly IntPtr HWND_TOP = IntPtr.Zero;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;
        private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

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

        // Deckt das Vordergrundfenster seinen ganzen Monitor ab und ist es
        // nicht die Shell/der Desktop?
        public static bool IsForegroundFullscreen()
        {
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
