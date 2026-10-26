#requires -Version 5.1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 FlashDragon (世界重构 / 庚辰)
param([switch]$HideConsole)
if ($HideConsole) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class LocalMusicPlayerConsole {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    $consoleHandle = [LocalMusicPlayerConsole]::GetConsoleWindow()
    if ($consoleHandle -ne [IntPtr]::Zero) {
        [void][LocalMusicPlayerConsole]::ShowWindow($consoleHandle, 0)
    }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore
$uiInteropSource=@"
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
internal class FileOpenDialogCom { }

[ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IFileDialogNative
{
    [PreserveSig] int Show(IntPtr parent);
    void SetFileTypes(uint count, IntPtr filters);
    void SetFileTypeIndex(uint index);
    void GetFileTypeIndex(out uint index);
    void Advise(IntPtr events, out uint cookie);
    void Unadvise(uint cookie);
    void SetOptions(uint options);
    void GetOptions(out uint options);
    void SetDefaultFolder(IShellItemNative folder);
    void SetFolder(IShellItemNative folder);
    void GetFolder(out IShellItemNative folder);
    void GetCurrentSelection(out IShellItemNative item);
    void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
    void GetFileName(out IntPtr name);
    void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
    void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
    void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
    void GetResult(out IShellItemNative item);
    void AddPlace(IShellItemNative item, uint location);
    void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension);
    void Close(int result);
    void SetClientGuid(ref Guid guid);
    void ClearClientData();
    void SetFilter(IntPtr filter);
}

[ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IShellItemNative
{
    void BindToHandler(IntPtr context, ref Guid handler, ref Guid iid, out IntPtr result);
    void GetParent(out IShellItemNative parent);
    void GetDisplayName(uint nameKind, out IntPtr name);
    void GetAttributes(uint mask, out uint attributes);
    void Compare(IShellItemNative other, uint hint, out int order);
}

public static class ModernFolderPicker
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        string path, IntPtr context, ref Guid iid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemNative item);

    public static uint ProbeOptions()
    {
        IFileDialogNative dialog = (IFileDialogNative)new FileOpenDialogCom();
        try { uint options; dialog.GetOptions(out options); return options; }
        finally { Marshal.ReleaseComObject(dialog); }
    }

    public static string Pick(IntPtr owner, string initialFolder)
    {
        IFileDialogNative dialog = null;
        IShellItemNative initial = null;
        IShellItemNative result = null;
        IntPtr name = IntPtr.Zero;
        try
        {
            dialog = (IFileDialogNative)new FileOpenDialogCom();
            uint options;
            dialog.GetOptions(out options);
            dialog.SetOptions(options | 0x20u | 0x40u); // PICKFOLDERS | FORCEFILESYSTEM
            dialog.SetTitle("选择音乐目录");
            dialog.SetOkButtonLabel("选择此文件夹");
            if (Directory.Exists(initialFolder))
            {
                Guid iid = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");
                SHCreateItemFromParsingName(initialFolder, IntPtr.Zero, ref iid, out initial);
                dialog.SetFolder(initial);
            }
            int hr = dialog.Show(owner);
            if (hr == unchecked((int)0x800704C7)) return null; // cancelled
            Marshal.ThrowExceptionForHR(hr);
            dialog.GetResult(out result);
            result.GetDisplayName(0x80058000u, out name); // SIGDN_FILESYSPATH
            return Marshal.PtrToStringUni(name);
        }
        finally
        {
            if (name != IntPtr.Zero) Marshal.FreeCoTaskMem(name);
            if (result != null) Marshal.ReleaseComObject(result);
            if (initial != null) Marshal.ReleaseComObject(initial);
            if (dialog != null) Marshal.ReleaseComObject(dialog);
        }
    }
}

public static class PlayerDwm
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string appName, string idList);

    public static void SetDarkTitleBar(IntPtr handle, bool dark)
    {
        int value = dark ? 1 : 0;
        try { DwmSetWindowAttribute(handle, 20, ref value, 4); }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }
    public static void SetBorderColor(IntPtr handle, Color color)
    {
        // DWMWA_BORDER_COLOR (Windows 11); COLORREF uses BGR byte order.
        int value = color.R | (color.G << 8) | (color.B << 16);
        try { DwmSetWindowAttribute(handle, 34, ref value, 4); }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }
    public static void SetListTheme(IntPtr handle, bool dark)
    {
        try { SetWindowTheme(handle, dark ? "DarkMode_Explorer" : "Explorer", null); }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }
}

public sealed class PlayerMenuColors : ProfessionalColorTable
{
    private readonly Color surface;
    private readonly Color hover;
    public PlayerMenuColors(bool dark)
    {
        surface = dark ? Color.FromArgb(36, 38, 42) : Color.FromArgb(248, 248, 248);
        hover = dark ? Color.FromArgb(65, 69, 76) : Color.FromArgb(222, 232, 244);
    }
    public override Color MenuStripGradientBegin { get { return surface; } }
    public override Color MenuStripGradientEnd { get { return surface; } }
    public override Color ToolStripDropDownBackground { get { return surface; } }
    public override Color ImageMarginGradientBegin { get { return surface; } }
    public override Color ImageMarginGradientMiddle { get { return surface; } }
    public override Color ImageMarginGradientEnd { get { return surface; } }
    public override Color MenuItemSelected { get { return hover; } }
    public override Color MenuItemSelectedGradientBegin { get { return hover; } }
    public override Color MenuItemSelectedGradientEnd { get { return hover; } }
    public override Color MenuItemPressedGradientBegin { get { return hover; } }
    public override Color MenuItemPressedGradientMiddle { get { return hover; } }
    public override Color MenuItemPressedGradientEnd { get { return hover; } }
    public override Color MenuBorder { get { return hover; } }
    public override Color MenuItemBorder { get { return hover; } }
}
public sealed class SlimSlider : Control
{
    private int minimum = 0;
    private int maximum = 100;
    private int current = 0;
    private bool dragging = false;
    public event EventHandler ValueChanged;
    public Color TrackColor { get; set; }
    public Color FillColor { get; set; }
    public Color ThumbColor { get; set; }

    public SlimSlider()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        TrackColor = Color.FromArgb(170, 174, 180);
        FillColor = SystemColors.Highlight;
        ThumbColor = SystemColors.Highlight;
        Height = 25;
    }
    public int Minimum { get { return minimum; } set { minimum = value; Value = current; } }
    public int Maximum { get { return maximum; } set { maximum = Math.Max(minimum + 1, value); Value = current; } }
    public int Value
    {
        get { return current; }
        set
        {
            int next = Math.Max(minimum, Math.Min(maximum, value));
            if (next == current) return;
            current = next;
            Invalidate();
            if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
        }
    }
    private void SetFromMouse(int x)
    {
        int width = Math.Max(1, ClientSize.Width - 16);
        double fraction = Math.Max(0.0, Math.Min(1.0, (x - 8) / (double)width));
        Value = minimum + (int)Math.Round((maximum - minimum) * fraction);
    }
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left)
        {
            dragging = true;
            Capture = true;
            SetFromMouse(e.X);
        }
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (dragging) SetFromMouse(e.X);
    }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (dragging)
        {
            SetFromMouse(e.X);
            dragging = false;
            Capture = false;
        }
        base.OnMouseUp(e);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        int left = 8, right = Math.Max(left + 1, ClientSize.Width - 8);
        int middle = ClientSize.Height / 2;
        int fill = left + (int)Math.Round((right - left) *
            ((current - minimum) / (double)Math.Max(1, maximum - minimum)));
        using (SolidBrush track = new SolidBrush(TrackColor))
            e.Graphics.FillRectangle(track, left, middle - 2, right - left, 4);
        using (SolidBrush progress = new SolidBrush(FillColor))
            e.Graphics.FillRectangle(progress, left, middle - 2, Math.Max(0, fill - left), 4);
        using (SolidBrush thumb = new SolidBrush(ThumbColor))
            e.Graphics.FillRectangle(thumb, fill - 5, middle - 7, 10, 14);
    }
}
"@
Add-Type -TypeDefinition $uiInteropSource -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll'
$folderListSource=@'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public sealed class FolderPresetList : ScrollableControl
{
    private sealed class Row
    {
        public string Path;
        public float Y;
        public Row(string path, float y) { Path = path; Y = y; }
    }
    private readonly List<Row> rows = new List<Row>();
    private readonly Timer animation = new Timer();
    private Row selected;
    private Row dragged;
    private int mouseDownY;
    private int dragOffset;
    private bool moved;
    private const int RowHeight = 54;
    public bool ReorderEnabled { get; set; }
    public string ActivePath { get; set; }
    public Color MutedColor { get; set; }
    public Color SelectedColor { get; set; }
    public Color ActiveColor { get; set; }
    public Color LineColor { get; set; }
    public event EventHandler SelectionChanged;
    public event EventHandler OrderChanged;
    public event EventHandler ItemActivated;

    public FolderPresetList()
    {
        DoubleBuffered = true;
        AutoScroll = true;
        TabStop = true;
        ReorderEnabled = true;
        MutedColor = Color.Gray;
        SelectedColor = Color.FromArgb(58, 80, 106);
        ActiveColor = SystemColors.Highlight;
        LineColor = Color.FromArgb(90, 90, 90);
        animation.Interval = 16;
        animation.Tick += delegate { AnimateRows(); };
    }
    public int SelectedIndex { get { return selected == null ? -1 : rows.IndexOf(selected); } }
    public string SelectedPath { get { return selected == null ? null : selected.Path; } }
    public string[] Paths
    {
        get
        {
            string[] values = new string[rows.Count];
            for (int i = 0; i < rows.Count; i++) values[i] = rows[i].Path;
            return values;
        }
    }
    public void SetPaths(string[] paths)
    {
        string previous = SelectedPath;
        rows.Clear();
        selected = null;
        dragged = null;
        animation.Stop();
        if (paths != null)
        {
            foreach (string path in paths)
            {
                Row row = new Row(path, rows.Count * RowHeight);
                rows.Add(row);
                if (previous != null && string.Equals(path, previous, StringComparison.OrdinalIgnoreCase))
                    selected = row;
            }
        }
        AutoScrollMinSize = new Size(0, rows.Count * RowHeight);
        Invalidate();
        OnSelectionChanged();
    }
    public void SelectPath(string path)
    {
        selected = null;
        foreach (Row row in rows)
            if (string.Equals(row.Path, path, StringComparison.OrdinalIgnoreCase)) { selected = row; break; }
        Invalidate();
        OnSelectionChanged();
    }
    private void OnSelectionChanged()
    {
        if (SelectionChanged != null) SelectionChanged(this, EventArgs.Empty);
    }
    private int RowAt(int y)
    {
        int index = (y - AutoScrollPosition.Y) / RowHeight;
        return index >= 0 && index < rows.Count ? index : -1;
    }
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        Focus();
        int index = RowAt(e.Y);
        selected = index < 0 ? null : rows[index];
        dragged = ReorderEnabled ? selected : null;
        mouseDownY = e.Y;
        dragOffset = selected == null ? 0 : e.Y - (int)selected.Y - AutoScrollPosition.Y;
        moved = false;
        Capture = true;
        Invalidate();
        OnSelectionChanged();
    }
    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (dragged == null || e.Button != MouseButtons.Left) return;
        if (!moved && Math.Abs(e.Y - mouseDownY) < 5) return;
        moved = true;
        dragged.Y = e.Y - AutoScrollPosition.Y - dragOffset;
        int current = rows.IndexOf(dragged);
        int target = Math.Max(0, Math.Min(rows.Count - 1,
            (int)Math.Floor((dragged.Y + RowHeight / 2.0) / RowHeight)));
        if (target != current)
        {
            rows.RemoveAt(current);
            rows.Insert(target, dragged);
        }
        animation.Start();
        Invalidate();
    }
    protected override void OnMouseUp(MouseEventArgs e)
    {
        bool changed = moved;
        dragged = null;
        moved = false;
        Capture = false;
        if (changed)
        {
            animation.Start();
            if (OrderChanged != null) OrderChanged(this, EventArgs.Empty);
        }
        base.OnMouseUp(e);
    }
    protected override void OnMouseDoubleClick(MouseEventArgs e)
    {
        base.OnMouseDoubleClick(e);
        if (SelectedPath != null && ItemActivated != null) ItemActivated(this, EventArgs.Empty);
    }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (rows.Count > 0 && (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down))
        {
            int current = SelectedIndex;
            int next = e.KeyCode == Keys.Down ? Math.Min(rows.Count - 1, current + 1)
                : Math.Max(0, current < 0 ? 0 : current - 1);
            selected = rows[next];
            int top = next * RowHeight;
            int viewTop = -AutoScrollPosition.Y;
            if (top < viewTop) AutoScrollPosition = new Point(0, top);
            else if (top + RowHeight > viewTop + ClientSize.Height)
                AutoScrollPosition = new Point(0, top + RowHeight - ClientSize.Height);
            Invalidate();
            OnSelectionChanged();
            e.Handled = true;
            return;
        }
        if (e.KeyCode == Keys.Enter && SelectedPath != null && ItemActivated != null)
        {
            ItemActivated(this, EventArgs.Empty);
            e.Handled = true;
            return;
        }
        base.OnKeyDown(e);
    }
    private void AnimateRows()
    {
        bool pending = false;
        for (int i = 0; i < rows.Count; i++)
        {
            Row row = rows[i];
            if (row == dragged) continue;
            float goal = i * RowHeight;
            if (Math.Abs(row.Y - goal) > 0.6f)
            {
                row.Y += (goal - row.Y) * 0.32f;
                pending = true;
            }
            else row.Y = goal;
        }
        Invalidate();
        if (!pending && dragged == null) animation.Stop();
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.Clear(BackColor);
        for (int i = 0; i < rows.Count; i++) if (rows[i] != dragged) DrawRow(e.Graphics, rows[i]);
        if (dragged != null) DrawRow(e.Graphics, dragged);
    }
    private void DrawRow(Graphics graphics, Row row)
    {
        int y = (int)Math.Round(row.Y) + AutoScrollPosition.Y;
        if (y > ClientSize.Height || y + RowHeight < 0) return;
        bool active = string.Equals(row.Path, ActivePath, StringComparison.OrdinalIgnoreCase);
        Rectangle bounds = new Rectangle(0, y, ClientSize.Width, RowHeight);
        Color fill = row == selected ? SelectedColor : BackColor;
        using (SolidBrush brush = new SolidBrush(fill)) graphics.FillRectangle(brush, bounds);
        if (active)
            using (SolidBrush brush = new SolidBrush(ActiveColor))
                graphics.FillRectangle(brush, 0, y + 5, 3, RowHeight - 10);
        using (Pen pen = new Pen(LineColor))
            graphics.DrawLine(pen, 8, y + RowHeight - 1, ClientSize.Width - 8, y + RowHeight - 1);
        string name = System.IO.Path.GetFileName(row.Path.TrimEnd('\\'));
        if (string.IsNullOrEmpty(name)) name = row.Path;
        Color primary = System.IO.Directory.Exists(row.Path) ? ForeColor : MutedColor;
        Rectangle title = new Rectangle(15, y + 4, ClientSize.Width - 28, 23);
        Rectangle detail = new Rectangle(15, y + 27, ClientSize.Width - 28, 20);
        TextRenderer.DrawText(graphics, name, Font, title, primary,
            TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter);
        TextRenderer.DrawText(graphics, row.Path, Font, detail, MutedColor,
            TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter);
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) animation.Dispose();
        base.Dispose(disposing);
    }
}

public static class FolderActionGlyphs
{
    public static Bitmap CreateBitmap(int kind, Color color)
    {
        Bitmap bitmap = new Bitmap(20, 20);
        using (Graphics graphics = Graphics.FromImage(bitmap))
        using (Pen pen = new Pen(color, 1.8f))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            if (kind == 0)
            {
                graphics.DrawLine(pen, 10, 3, 10, 17);
                graphics.DrawLine(pen, 3, 10, 17, 10);
            }
            else if (kind == 1)
            {
                graphics.DrawLine(pen, 4, 5, 16, 5);
                graphics.DrawLine(pen, 7, 3, 13, 3);
                graphics.DrawRectangle(pen, 5, 7, 10, 10);
                graphics.DrawLine(pen, 8, 9, 8, 15);
                graphics.DrawLine(pen, 12, 9, 12, 15);
            }
            else
            {
                graphics.DrawLine(pen, 4, 15, 14, 5);
                graphics.DrawLine(pen, 6, 17, 16, 7);
                graphics.DrawLine(pen, 3, 17, 6, 17);
                graphics.DrawLine(pen, 14, 5, 16, 7);
            }
        }
        return bitmap;
    }
}

public sealed class ThemedPlaylistButton : Button
{
    private bool over;
    private bool down;
    public Color HoverColor { get; set; }
    public Color PressedColor { get; set; }
    public Color DisabledBackColor { get; set; }
    public Color DisabledForeColor { get; set; }
    public Color FocusColor { get; set; }
    public ThemedPlaylistButton()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer, true);
        HoverColor = Color.FromArgb(68, 72, 79);
        PressedColor = Color.FromArgb(76, 80, 88);
        DisabledBackColor = Color.FromArgb(46, 48, 52);
        DisabledForeColor = Color.FromArgb(145, 150, 158);
        FocusColor = Color.FromArgb(100, 100, 100);
        FlatStyle = FlatStyle.Flat;
        TabStop = true;
    }
    protected override void OnMouseEnter(EventArgs e) { over = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { over = false; down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) down = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnPaint(PaintEventArgs e)
    {
        Color fill = !Enabled ? DisabledBackColor : down ? PressedColor : over ? HoverColor : BackColor;
        using (SolidBrush brush = new SolidBrush(fill)) e.Graphics.FillRectangle(brush, ClientRectangle);
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle,
            Enabled ? ForeColor : DisabledForeColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
        if (Focused && Enabled)
        {
            using (Pen pen = new Pen(FocusColor))
                e.Graphics.DrawRectangle(pen, 1, 1, Math.Max(0, Width - 3), Math.Max(0, Height - 3));
        }
    }
}
'@
Add-Type -TypeDefinition $folderListSource -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll'
$taskbarSource=@"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComImport, Guid("56FDF344-FD6D-11D0-958A-006097C9A090")]
internal class TaskbarListCom { }

[ComImport, Guid("EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface ITaskbarList3Native
{
    void HrInit();
    void AddTab(IntPtr hwnd);
    void DeleteTab(IntPtr hwnd);
    void ActivateTab(IntPtr hwnd);
    void SetActiveAlt(IntPtr hwnd);
    void MarkFullscreenWindow(IntPtr hwnd, [MarshalAs(UnmanagedType.Bool)] bool fullscreen);
    void SetProgressValue(IntPtr hwnd, ulong completed, ulong total);
    void SetProgressState(IntPtr hwnd, uint flags);
    void RegisterTab(IntPtr tab, IntPtr parent);
    void UnregisterTab(IntPtr tab);
    void SetTabOrder(IntPtr tab, IntPtr before);
    void SetTabActive(IntPtr tab, IntPtr parent, uint reserved);
    void ThumbBarAddButtons(IntPtr hwnd, uint count, [In, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] ThumbButton[] buttons);
    void ThumbBarUpdateButtons(IntPtr hwnd, uint count, [In, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] ThumbButton[] buttons);
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
internal struct ThumbButton
{
    public uint Mask;
    public uint Id;
    public uint Bitmap;
    public IntPtr Icon;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Tip;
    public uint Flags;
}

public sealed class ThumbnailCommandEventArgs : EventArgs
{
    public int CommandId { get; private set; }
    public ThumbnailCommandEventArgs(int commandId) { CommandId = commandId; }
}

public sealed class PlayerForm : Form
{
    private const int WmCommand = 0x0111;
    private const int ThumbClicked = 0x1800;
    private static readonly int TaskbarCreated = RegisterWindowMessage("TaskbarButtonCreated");
    private ThumbnailToolbar toolbar;
    private bool playing;
    private bool hasTracks;
    private bool progressActive;
    private bool progressPaused;
    private ulong progressCompleted;
    private ulong progressTotal;
    public event EventHandler<ThumbnailCommandEventArgs> ThumbnailCommand;
    public bool ThumbnailReady { get { return toolbar != null; } }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int RegisterWindowMessage(string message);

    public void SetThumbnailState(bool isPlaying, bool tracksAvailable)
    {
        playing = isPlaying;
        hasTracks = tracksAvailable;
        if (toolbar != null)
        {
            try { toolbar.Update(playing, hasTracks); }
            catch { toolbar.Dispose(); toolbar = null; }
        }
    }
    public void SetPlaybackProgress(bool active, bool paused, ulong completed, ulong total)
    {
        progressActive = active && total > 0;
        progressPaused = paused;
        progressTotal = total;
        progressCompleted = Math.Min(completed, total);
        if (toolbar != null)
        {
            try { toolbar.SetProgress(progressActive, progressPaused, progressCompleted, progressTotal); }
            catch { }
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmCommand && (((long)m.WParam >> 16) & 0xffff) == ThumbClicked)
        {
            int id = (int)((long)m.WParam & 0xffff);
            if (id >= 1 && id <= 4)
            {
                EventHandler<ThumbnailCommandEventArgs> handler = ThumbnailCommand;
                if (handler != null) handler(this, new ThumbnailCommandEventArgs(id));
                m.Result = IntPtr.Zero;
                return;
            }
        }
        base.WndProc(ref m);
        if (m.Msg == TaskbarCreated)
        {
            if (toolbar != null) toolbar.Dispose();
            toolbar = null;
            try
            {
                toolbar = new ThumbnailToolbar(Handle);
                toolbar.Add(playing, hasTracks);
                toolbar.SetProgress(progressActive, progressPaused, progressCompleted, progressTotal);
            }
            catch
            {
                if (toolbar != null) toolbar.Dispose();
                toolbar = null;
            }
        }
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        if (toolbar != null) { toolbar.Dispose(); toolbar = null; }
        base.OnHandleDestroyed(e);
    }
}

internal sealed class ThumbnailToolbar : IDisposable
{
    private const uint MaskIconTipFlags = 0x2 | 0x4 | 0x8;
    private const uint Disabled = 0x1;
    private readonly IntPtr hwnd;
    private readonly ITaskbarList3Native native;
    private readonly IntPtr[] icons = new IntPtr[5];
    private bool added;
    private bool lastPlaying;
    private bool lastAvailable;
    private uint lastProgressState = uint.MaxValue;
    private ulong lastCompleted = ulong.MaxValue;
    private ulong lastTotal = ulong.MaxValue;

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr icon);

    public ThumbnailToolbar(IntPtr window)
    {
        hwnd = window;
        native = (ITaskbarList3Native)new TaskbarListCom();
        native.HrInit();
        for (int i = 0; i < icons.Length; i++) icons[i] = CreateIcon(i);
    }

    private static IntPtr CreateIcon(int kind)
    {
        using (Bitmap bitmap = PlayerGlyphs.CreateBitmap(kind, Color.FromArgb(235, 239, 243)))
            return bitmap.GetHicon();
    }

    private ThumbButton[] Build(bool playing, bool available)
    {
        return new [] {
            Button(1, icons[0], "上一首", available),
            Button(2, icons[1], "停止", available),
            Button(3, icons[playing ? 4 : 2], playing ? "暂停" : "播放", available),
            Button(4, icons[3], "下一首", available)
        };
    }

    private static ThumbButton Button(uint id, IntPtr icon, string tip, bool enabled)
    {
        return new ThumbButton { Mask = MaskIconTipFlags, Id = id, Icon = icon, Tip = tip, Flags = enabled ? 0u : Disabled };
    }

    public void Add(bool playing, bool available)
    {
        native.ThumbBarAddButtons(hwnd, 4, Build(playing, available));
        added = true;
        lastPlaying = playing;
        lastAvailable = available;
    }

    public void Update(bool playing, bool available)
    {
        if (!added || (lastPlaying == playing && lastAvailable == available)) return;
        native.ThumbBarUpdateButtons(hwnd, 4, Build(playing, available));
        lastPlaying = playing;
        lastAvailable = available;
    }

    public void SetProgress(bool active, bool paused, ulong completed, ulong total)
    {
        uint state = !active || total == 0 ? 0u : paused ? 8u : 2u;
        if (state != lastProgressState)
        {
            native.SetProgressState(hwnd, state);
            lastProgressState = state;
        }
        if (state != 0 && (completed != lastCompleted || total != lastTotal))
        {
            native.SetProgressValue(hwnd, Math.Min(completed, total), total);
            lastCompleted = completed;
            lastTotal = total;
        }
    }

    public void Dispose()
    {
        try { native.SetProgressState(hwnd, 0u); } catch { }
        for (int i = 0; i < icons.Length; i++)
            if (icons[i] != IntPtr.Zero) { DestroyIcon(icons[i]); icons[i] = IntPtr.Zero; }
        if (native != null) Marshal.ReleaseComObject(native);
    }
}

public static class PlayerGlyphs
{
    public static Bitmap CreateBitmap(int kind, Color color)
    {
        Bitmap bitmap = new Bitmap(24, 24);
        using (Graphics g = Graphics.FromImage(bitmap))
        using (Brush brush = new SolidBrush(color))
        {
            g.Clear(Color.Transparent);
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            if (kind == 0)
            {
                g.FillRectangle(brush, 3, 5, 2, 14);
                g.FillPolygon(brush, new [] { new PointF(5, 12), new PointF(11, 5), new PointF(11, 19) });
                g.FillPolygon(brush, new [] { new PointF(11, 12), new PointF(19, 5), new PointF(19, 19) });
            }
            else if (kind == 3)
            {
                g.FillPolygon(brush, new [] { new PointF(5, 5), new PointF(5, 19), new PointF(13, 12) });
                g.FillPolygon(brush, new [] { new PointF(13, 5), new PointF(13, 19), new PointF(19, 12) });
                g.FillRectangle(brush, 19, 5, 2, 14);
            }
            else if (kind == 1) g.FillRectangle(brush, 6, 6, 12, 12);
            else if (kind == 2) g.FillPolygon(brush, new [] { new PointF(6, 4), new PointF(6, 20), new PointF(19, 12) });
            else if (kind == 4) { g.FillRectangle(brush, 6, 5, 4, 14); g.FillRectangle(brush, 14, 5, 4, 14); }
            else if (kind == 5 || kind == 6)
            {
                g.FillPolygon(brush, new [] { new PointF(2, 9), new PointF(6, 9), new PointF(12, 5),
                                               new PointF(12, 19), new PointF(6, 15), new PointF(2, 15) });
                using (Pen pen = new Pen(color, 1.6f))
                {
                    if (kind == 5)
                    {
                        g.DrawArc(pen, 10, 6, 8, 12, -60, 120);
                        g.DrawArc(pen, 9, 3, 14, 18, -60, 120);
                    }
                    else
                    {
                        g.DrawLine(pen, 16, 9, 22, 15);
                        g.DrawLine(pen, 22, 9, 16, 15);
                    }
                }
            }
        }
        return bitmap;
    }
}
"@
Add-Type -TypeDefinition $taskbarSource -ReferencedAssemblies 'System.Windows.Forms.dll','System.Drawing.dll'
$programDir=if($PSScriptRoot){$PSScriptRoot}else{[AppDomain]::CurrentDomain.BaseDirectory}
$tagLibPath=Join-Path $programDir 'TagLibSharp.dll'
if(-not [IO.File]::Exists($tagLibPath)){
  [void][Windows.Forms.MessageBox]::Show('缺少 TagLibSharp.dll，请将它与播放器放在同一目录。','LocalMusicPlayer')
  return
}
Add-Type -Path $tagLibPath -ErrorAction Stop
function Get-SongInfo([string]$filePath) {
  $info=[pscustomobject]@{
    Title=[IO.Path]::GetFileNameWithoutExtension($filePath)
    Composer='未标注'
    CreditLabel='作曲家'
    Album='未标注'
    Year='未标注'
    CoverBytes=$null
  }
  $media=$null
  try {
    $media=[TagLib.File]::Create($filePath)
    $tag=$media.Tag
    if(-not [string]::IsNullOrWhiteSpace($tag.Title)){$info.Title=$tag.Title}
    $composers=@($tag.Composers|Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
    if($composers.Count -gt 0){$info.Composer=$composers -join ' / '}
    else{
      $artists=@($tag.Performers|Where-Object {-not [string]::IsNullOrWhiteSpace($_)})
      if($artists.Count -gt 0){$info.Composer=$artists -join ' / ';$info.CreditLabel='艺术家'}
    }
    if(-not [string]::IsNullOrWhiteSpace($tag.Album)){$info.Album=$tag.Album}
    if($tag.Year -gt 0){$info.Year=[string]$tag.Year}
    $pictures=@($tag.Pictures)
    $picture=$pictures|Where-Object {$_.Type -eq [TagLib.PictureType]::FrontCover}|Select-Object -First 1
    if(-not $picture){$picture=$pictures|Select-Object -First 1}
    if($picture -and $picture.Data -and $picture.Data.Count -gt 0 -and $picture.Data.Count -le 10MB){
      $info.CoverBytes=[byte[]]$picture.Data.Data
    }
  }catch{}
  finally{if($media){$media.Dispose()}}
  if(-not $info.CoverBytes){
    $folder=[IO.Path]::GetDirectoryName($filePath)
    foreach($name in @('cover.jpg','folder.jpg','front.jpg','album.jpg','cover.png','folder.png')){
      try{
        $image=[IO.Path]::Combine($folder,$name)
        if([IO.File]::Exists($image) -and ([IO.FileInfo]::new($image)).Length -le 10MB){
          $info.CoverBytes=[IO.File]::ReadAllBytes($image)
          break
        }
      }catch{}
    }
  }
  return $info
}
[Windows.Forms.Application]::EnableVisualStyles()
$script:path=Join-Path $env:USERPROFILE 'Music'
if(-not [IO.Directory]::Exists($script:path)){
  $knownMusic=[Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic)
  if([IO.Directory]::Exists($knownMusic)){$script:path=$knownMusic}
}
$script:config=Join-Path $env:LOCALAPPDATA 'LocalMusicPlayer\settings.json'
$legacyConfig=Join-Path $env:LOCALAPPDATA 'RandomMusicPlayer\settings.json'
if(-not [IO.File]::Exists($script:config) -and [IO.File]::Exists($legacyConfig)){
  try{
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:config))
    [IO.File]::Move($legacyConfig,$script:config)
    $oldFolder=[IO.Path]::GetDirectoryName($legacyConfig)
    if([IO.Directory]::GetFileSystemEntries($oldFolder).Length -eq 0){[IO.Directory]::Delete($oldFolder)}
  }catch{}
}
$script:vol=70
$script:muted=$false
$script:mode='random'
$script:modeIds=@('list-once','list-loop','single-once','single-loop','random')
$script:presets=[Collections.Generic.List[string]]::new()
$script:recentFolders=[Collections.Generic.List[string]]::new()
function Normalize-FolderPath([string]$candidate) {
  if([string]::IsNullOrWhiteSpace($candidate)){return $null}
  try {
    $expanded=[Environment]::ExpandEnvironmentVariables($candidate.Trim().Trim('"'))
    $full=[IO.Path]::GetFullPath($expanded)
    $root=[IO.Path]::GetPathRoot($full)
    if($full.Length -gt $root.Length){$full=$full.TrimEnd('\','/')}
    return $full
  }catch{return $null}
}
function Find-FolderIndex($folders,[string]$candidate) {
  for($i=0;$i -lt $folders.Count;$i++){
    if([string]::Equals($folders[$i],$candidate,[StringComparison]::OrdinalIgnoreCase)){return $i}
  }
  return -1
}
function Record-RecentFolder([string]$candidate) {
  $pathToRecord=Normalize-FolderPath $candidate
  if(-not $pathToRecord){return}
  $existing=Find-FolderIndex $script:recentFolders $pathToRecord
  if($existing -ge 0){$script:recentFolders.RemoveAt($existing)}
  $script:recentFolders.Insert(0,$pathToRecord)
  while($script:recentFolders.Count -gt 64){$script:recentFolders.RemoveAt(64)}
}
$settingsToRead=if([IO.File]::Exists($script:config)){$script:config}elseif([IO.File]::Exists($legacyConfig)){$legacyConfig}else{$null}
if($settingsToRead){
  try {$s=Get-Content -LiteralPath $settingsToRead -Raw|ConvertFrom-Json
    if($s.Path -and (Test-Path -LiteralPath $s.Path -PathType Container)){$script:path=$s.Path}
    if($null -ne $s.Volume){$script:vol=[Math]::Max(0,[Math]::Min(100,[int]$s.Volume))}
    if($null -ne $s.Muted){$script:muted=[bool]$s.Muted}
    if($s.Mode -and $script:modeIds -contains [string]$s.Mode){$script:mode=[string]$s.Mode}
    foreach($folder in @($s.PresetFolders)){
      $normalized=Normalize-FolderPath ([string]$folder)
      if($normalized -and (Find-FolderIndex $script:presets $normalized) -lt 0){$script:presets.Add($normalized)}
    }
    foreach($folder in @($s.RecentFolders)){
      $normalized=Normalize-FolderPath ([string]$folder)
      if($normalized -and (Find-FolderIndex $script:recentFolders $normalized) -lt 0){$script:recentFolders.Add($normalized)}
      if($script:recentFolders.Count -ge 64){break}
    }
  }catch{}
}
function Save-Config {
  try {[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:config))
    @{Path=$script:path;Volume=$script:vol;Muted=$script:muted;Mode=$script:mode;
      PresetFolders=$script:presets.ToArray();RecentFolders=$script:recentFolders.ToArray()}|
      ConvertTo-Json -Depth 4|Set-Content -LiteralPath $script:config -Encoding UTF8
  }catch{}
}
$script:player=[Windows.Media.MediaPlayer]::new()
$script:player.Volume=if($script:muted){0.0}else{$script:vol/100.0}
$script:lastAudibleVol=if($script:vol -gt 0){$script:vol}else{70}
$script:tracks=@()
$script:bag=[Collections.Generic.List[int]]::new()
$script:history=[Collections.Generic.List[int]]::new()
$script:historyPos=-1
$script:current=-1
$script:playing=$false
$script:paused=$false
$script:seeking=$false
$extensions=@('.mp3','.wav','.wma','.m4a','.aac','.flac','.ogg')
$form=[PlayerForm]::new()
$form.Text='LocalMusicPlayer'
$form.Size=[Drawing.Size]::new(930,560)
$form.MinimumSize=[Drawing.Size]::new(760,450)
$form.StartPosition='CenterScreen'
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)
try {
  $iconFile=Join-Path $programDir 'LocalMusicPlayer.exe'
  if([IO.File]::Exists($iconFile)){$form.Icon=[Drawing.Icon]::ExtractAssociatedIcon($iconFile)}
} catch {}

$menu=[Windows.Forms.MenuStrip]::new()
$fileMenu=[Windows.Forms.ToolStripMenuItem]::new('文件')
$chooseMenu=[Windows.Forms.ToolStripMenuItem]::new('选择音乐目录...')
$addressMenu=[Windows.Forms.ToolStripMenuItem]::new('输入目录地址...')
$rescanMenu=[Windows.Forms.ToolStripMenuItem]::new('重新扫描')
$exitMenu=[Windows.Forms.ToolStripMenuItem]::new('退出')
[void]$fileMenu.DropDownItems.Add($chooseMenu)
[void]$fileMenu.DropDownItems.Add($addressMenu)
[void]$fileMenu.DropDownItems.Add($rescanMenu)
[void]$fileMenu.DropDownItems.Add($exitMenu)
$playlistMenu=[Windows.Forms.ToolStripMenuItem]::new('播放列表')
$modeMenu=[Windows.Forms.ToolStripMenuItem]::new('播放模式')
$modeNames=@('播放一遍列表','列表循环','播放一遍单曲','单曲循环','随机播放')
$modeMenuItems=@()
for($i=0;$i -lt $script:modeIds.Count;$i++){
  $item=[Windows.Forms.ToolStripMenuItem]::new($modeNames[$i])
  $item.Tag=$script:modeIds[$i]
  $item.Checked=($script:mode -eq $script:modeIds[$i])
  [void]$modeMenu.DropDownItems.Add($item)
  $modeMenuItems+=,$item
}
[void]$menu.Items.Add($fileMenu)
[void]$menu.Items.Add($playlistMenu)
[void]$menu.Items.Add($modeMenu)
$aboutMenu=[Windows.Forms.ToolStripMenuItem]::new('关于')
[void]$menu.Items.Add($aboutMenu)
$form.MainMenuStrip=$menu

$body=[Windows.Forms.TableLayoutPanel]::new()
$body.Dock='Fill'
$body.Padding=[Windows.Forms.Padding]::new(10,6,10,8)
$body.RowCount=4;$body.ColumnCount=1
[void]$body.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
foreach($h in @(42,60,34)){[void]$body.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$h))}
$frame=[Windows.Forms.TableLayoutPanel]::new()
$frame.Dock='Fill';$frame.ColumnCount=1;$frame.RowCount=2
[void]$frame.RowStyles.Add([Windows.Forms.RowStyle]::new('AutoSize',0))
[void]$frame.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
$menu.Dock='Fill'
[void]$frame.Controls.Add($menu,0,0)
[void]$frame.Controls.Add($body,0,1)
[void]$form.Controls.Add($frame)

$infoPanel=[Windows.Forms.TableLayoutPanel]::new()
$infoPanel.Dock='Fill';$infoPanel.ColumnCount=2;$infoPanel.RowCount=1
[void]$infoPanel.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
[void]$infoPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',275))
[void]$infoPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))

$metaPanel=[Windows.Forms.TableLayoutPanel]::new()
$metaPanel.Dock='Top';$metaPanel.Height=312;$metaPanel.ColumnCount=1;$metaPanel.RowCount=5
foreach($h in @(166,42,32,40,32)){[void]$metaPanel.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',$h))}
$cover=[Windows.Forms.PictureBox]::new()
$cover.Size=[Drawing.Size]::new(144,144)
$cover.SizeMode='Zoom'
$cover.BorderStyle='FixedSingle'
$cover.Margin=[Windows.Forms.Padding]::new(8,8,8,8)
$cover.Anchor='Top,Left'
try {
  if($form.Icon){$script:placeholderArt=$form.Icon.ToBitmap()}
  else{$script:placeholderArt=[Drawing.Bitmap]::new(144,144)}
} catch {$script:placeholderArt=[Drawing.Bitmap]::new(144,144)}
$cover.Image=$script:placeholderArt
[void]$metaPanel.Controls.Add($cover,0,0)

$now=[Windows.Forms.Label]::new()
$now.Text='尚未播放';$now.Font=[Drawing.Font]::new('Microsoft YaHei UI',11,[Drawing.FontStyle]::Bold)
$composerLabel=[Windows.Forms.Label]::new();$composerLabel.Text='作曲家：—'
$albumLabel=[Windows.Forms.Label]::new();$albumLabel.Text='专辑：—'
$yearLabel=[Windows.Forms.Label]::new();$yearLabel.Text='年份：—'
$metaLabels=@($now,$composerLabel,$albumLabel,$yearLabel)
for($i=0;$i -lt $metaLabels.Count;$i++){
  $metaLabels[$i].Dock='Fill'
  $metaLabels[$i].TextAlign='MiddleLeft'
  $metaLabels[$i].AutoEllipsis=$true
  $metaLabels[$i].Margin=[Windows.Forms.Padding]::new(8,2,8,2)
  [void]$metaPanel.Controls.Add($metaLabels[$i],0,$i+1)
}
[void]$infoPanel.Controls.Add($metaPanel,0,0)

$list=[Windows.Forms.ListView]::new()
$list.Dock='Fill';$list.View='Details'
$list.FullRowSelect=$true;$list.HideSelection=$false;$list.MultiSelect=$false
$list.HeaderStyle='Nonclickable';$list.GridLines=$false;$list.OwnerDraw=$true
$list.Margin=[Windows.Forms.Padding]::new(8,4,0,5)
$list.Add_HandleCreated({
  if($null -ne $script:themeDark){[PlayerDwm]::SetListTheme($list.Handle,[bool]$script:themeDark)}
})
[void]$list.Columns.Add('序号',58)
[void]$list.Columns.Add('曲目',500)
$list.Add_DrawColumnHeader({
  param($sender,$e)
  if($script:themeDark){
    $background=[Drawing.Color]::FromArgb(47,49,54)
    $foreground=[Drawing.Color]::FromArgb(238,239,242)
    $edge=[Drawing.Color]::FromArgb(83,87,95)
  }else{
    $background=[Drawing.Color]::FromArgb(236,238,241)
    $foreground=[Drawing.Color]::FromArgb(25,27,30)
    $edge=[Drawing.Color]::FromArgb(180,184,190)
  }
  $brush=[Drawing.SolidBrush]::new($background)
  $pen=[Drawing.Pen]::new($edge)
  try{
    $e.Graphics.FillRectangle($brush,$e.Bounds)
    $e.Graphics.DrawLine($pen,$e.Bounds.Left,$e.Bounds.Bottom-1,$e.Bounds.Right,$e.Bounds.Bottom-1)
    $textBounds=[Drawing.Rectangle]::new($e.Bounds.Left+6,$e.Bounds.Top,$e.Bounds.Width-8,$e.Bounds.Height)
    $flags=[Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis
    [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$e.Header.Text,$list.Font,$textBounds,$foreground,$flags)
  }finally{$brush.Dispose();$pen.Dispose()}
})
$list.Add_DrawItem({
  param($sender,$e)
  $e.DrawDefault=$false
})
$list.Add_DrawSubItem({
  param($sender,$e)
  $background=if($e.Item.Selected){$script:accent}else{$list.BackColor}
  $foreground=if($e.Item.Selected){Get-AccentTextColor $script:accent}else{$list.ForeColor}
  $brush=[Drawing.SolidBrush]::new($background)
  try{
    $e.Graphics.FillRectangle($brush,$e.Bounds)
    $textBounds=[Drawing.Rectangle]::new($e.Bounds.Left+6,$e.Bounds.Top,[Math]::Max(0,$e.Bounds.Width-8),$e.Bounds.Height)
    $flags=[Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis
    [Windows.Forms.TextRenderer]::DrawText($e.Graphics,$e.SubItem.Text,$list.Font,$textBounds,$foreground,$flags)
  }finally{$brush.Dispose()}
})
[void]$infoPanel.Controls.Add($list,1,0)
[void]$body.Controls.Add($infoPanel,0,0)

$seekPanel=[Windows.Forms.TableLayoutPanel]::new()
$seekPanel.Dock='Fill';$seekPanel.ColumnCount=2;$seekPanel.RowCount=1
[void]$seekPanel.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
[void]$seekPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
[void]$seekPanel.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',135))
$seek=[SlimSlider]::new()
$seek.Minimum=0;$seek.Maximum=1000;$seek.Dock='Fill'
$seek.Margin=[Windows.Forms.Padding]::new(0,5,5,5)
$clock=[Windows.Forms.Label]::new()
$clock.Text='00:00 / 00:00';$clock.Dock='Fill';$clock.TextAlign='MiddleRight'
[void]$seekPanel.Controls.Add($seek,0,0)
[void]$seekPanel.Controls.Add($clock,1,0)
[void]$body.Controls.Add($seekPanel,0,1)

$bar=[Windows.Forms.TableLayoutPanel]::new()
$bar.Dock='Fill';$bar.ColumnCount=8;$bar.RowCount=1
[void]$bar.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
foreach($w in @(48,48,48,48,-1,64,120,62)){
  if($w -lt 0){[void]$bar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))}
  else{[void]$bar.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',$w))}
}
$prev=[Windows.Forms.Button]::new();$prev.AccessibleName='上一首'
$play=[Windows.Forms.Button]::new();$play.AccessibleName='播放'
$next=[Windows.Forms.Button]::new();$next.AccessibleName='下一首'
$stop=[Windows.Forms.Button]::new();$stop.AccessibleName='停止'
$spacer=[Windows.Forms.Panel]::new()
$muteButton=[Windows.Forms.Button]::new();$muteButton.AccessibleName='静音'
$volume=[SlimSlider]::new();$volume.Minimum=0;$volume.Maximum=100;$volume.Value=$script:vol
$volPercent=[Windows.Forms.Label]::new();$volPercent.Text="$script:vol%";$volPercent.TextAlign='MiddleRight'
$controls=@($prev,$stop,$play,$next,$spacer,$muteButton,$volume,$volPercent)
for($i=0;$i -lt $controls.Count;$i++){
  $controls[$i].Dock='Fill'
  if($i -lt 4){$controls[$i].Margin=[Windows.Forms.Padding]::new(0,8,3,8)}
  elseif($i -eq 5){$controls[$i].Margin=[Windows.Forms.Padding]::new(10,8,8,8)}
  elseif($i -eq 6){$controls[$i].Margin=[Windows.Forms.Padding]::new(0,12,0,12)}
  [void]$bar.Controls.Add($controls[$i],$i,0)
}
[void]$body.Controls.Add($bar,0,2)

$status=[Windows.Forms.Label]::new()
$status.Dock='Fill';$status.TextAlign='MiddleLeft';$status.AutoEllipsis=$true
[void]$body.Controls.Add($status,0,3)
$toolTip=[Windows.Forms.ToolTip]::new()
$toolTip.SetToolTip($cover,'当前曲目的专辑封面')
$toolTip.SetToolTip($volume,'滚轮每格调整 5% 音量')
$toolTip.SetToolTip($prev,'上一首')
$toolTip.SetToolTip($next,'下一首')
$toolTip.SetToolTip($stop,'停止')

function Set-TransportIcon($button,[int]$kind,[Drawing.Color]$color) {
  $key="$kind/$($color.ToArgb())"
  if($button.Tag -eq $key){return}
  $old=$button.Image
  $button.Image=[PlayerGlyphs]::CreateBitmap($kind,$color)
  $button.Tag=$key
  if($old){$old.Dispose()}
}
function Update-TransportIcons {
  $color=if($script:themeDark){[Drawing.Color]::FromArgb(235,239,243)}else{[Drawing.Color]::FromArgb(65,69,76)}
  Set-TransportIcon $prev 0 $color
  Set-TransportIcon $stop 1 $color
  Set-TransportIcon $next 3 $color
  $kind=if($script:playing){4}else{2}
  Set-TransportIcon $play $kind $color
  $name=if($script:playing){'暂停'}else{'播放'}
  $play.AccessibleName=$name
  $toolTip.SetToolTip($play,$name)
  Update-VolumeIcon
}
function Update-VolumeIcon {
  $color=if($script:themeDark){[Drawing.Color]::FromArgb(235,239,243)}else{[Drawing.Color]::FromArgb(65,69,76)}
  $silent=$script:muted -or $script:vol -eq 0
  Set-TransportIcon $muteButton $(if($silent){6}else{5}) $color
  $name=if($silent){'取消静音'}else{'静音'}
  $muteButton.AccessibleName=$name
  $toolTip.SetToolTip($muteButton,$name)
}
function Apply-Volume {
  $script:player.Volume=if($script:muted){0.0}else{$script:vol/100.0}
  Update-VolumeIcon
}
function Update-TaskbarProgress {
  if($script:current -lt 0 -or (-not $script:playing -and -not $script:paused) -or
     -not $script:player.NaturalDuration.HasTimeSpan){
    $form.SetPlaybackProgress($false,$false,[uint64]0,[uint64]0)
    return
  }
  $duration=[int64]$script:player.NaturalDuration.TimeSpan.Ticks
  if($duration -le 0){$form.SetPlaybackProgress($false,$false,[uint64]0,[uint64]0);return}
  $elapsed=[int64]$script:player.Position.Ticks
  if($elapsed -lt 0){$elapsed=0}
  if($elapsed -gt $duration){$elapsed=$duration}
  $form.SetPlaybackProgress($true,$script:paused,[uint64]$elapsed,[uint64]$duration)
}

$script:themeDark=$null
$script:accent=[Drawing.SystemColors]::Highlight
function Get-AppDarkTheme {
  try {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize')
    if($null -eq $key){return $false}
    try { return ([int]$key.GetValue('AppsUseLightTheme',1) -eq 0) }
    finally { $key.Dispose() }
  } catch { return $false }
}
function Get-SystemAccentColor {
  try {
    $type=[Windows.UI.ViewManagement.UISettings,Windows,ContentType=WindowsRuntime]
    $settings=[Activator]::CreateInstance($type)
    $kind=[Windows.UI.ViewManagement.UIColorType,Windows,ContentType=WindowsRuntime]::Accent
    $color=$settings.GetColorValue($kind)
    return [Drawing.Color]::FromArgb([int]$color.R,[int]$color.G,[int]$color.B)
  }catch{return [Drawing.SystemColors]::Highlight}
}
function Blend-Color([Drawing.Color]$base,[Drawing.Color]$overlay,[double]$amount) {
  $amount=[Math]::Max(0,[Math]::Min(1,$amount))
  return [Drawing.Color]::FromArgb(
    [int][Math]::Round($base.R*(1-$amount)+$overlay.R*$amount),
    [int][Math]::Round($base.G*(1-$amount)+$overlay.G*$amount),
    [int][Math]::Round($base.B*(1-$amount)+$overlay.B*$amount))
}
function Get-AccentTextColor([Drawing.Color]$color) {
  $brightness=($color.R*299+$color.G*587+$color.B*114)/1000
  if($brightness -gt 150){return [Drawing.Color]::FromArgb(20,22,25)}
  return [Drawing.Color]::White
}
function Apply-Theme([bool]$force=$false) {
  $dark=Get-AppDarkTheme
  $accent=Get-SystemAccentColor
  if(-not $force -and $null -ne $script:themeDark -and $script:themeDark -eq $dark -and
    $script:accent.ToArgb() -eq $accent.ToArgb()){return}
  $script:themeDark=$dark
  $script:accent=$accent
  if($dark){
    $surface=[Drawing.Color]::FromArgb(30,32,36)
    $input=[Drawing.Color]::FromArgb(42,44,49)
    $button=[Drawing.Color]::FromArgb(53,56,62)
    $hover=[Drawing.Color]::FromArgb(68,72,79)
    $border=[Drawing.Color]::FromArgb(83,87,95)
    $text=[Drawing.Color]::FromArgb(238,239,242)
    $muted=[Drawing.Color]::FromArgb(181,185,193)
    $track=[Drawing.Color]::FromArgb(89,93,101)
  }else{
    $surface=[Drawing.Color]::FromArgb(242,242,242)
    $input=[Drawing.Color]::White
    $button=[Drawing.Color]::FromArgb(249,249,249)
    $hover=[Drawing.Color]::FromArgb(226,234,244)
    $border=[Drawing.Color]::FromArgb(180,184,190)
    $text=[Drawing.Color]::FromArgb(25,27,30)
    $muted=[Drawing.Color]::FromArgb(80,80,80)
    $track=[Drawing.Color]::FromArgb(171,176,182)
  }
  foreach($panel in @($form,$frame,$body,$infoPanel,$metaPanel,$seekPanel,$bar,$spacer)){$panel.BackColor=$surface}
  $menu.BackColor=$surface;$menu.ForeColor=$text
  $menu.Renderer=[Windows.Forms.ToolStripProfessionalRenderer]::new([PlayerMenuColors]::new($dark))
  foreach($dropDown in @($fileMenu.DropDown,$modeMenu.DropDown)){$dropDown.BackColor=$surface}
  foreach($item in @($fileMenu,$chooseMenu,$addressMenu,$rescanMenu,$exitMenu,$playlistMenu,$modeMenu,$aboutMenu)+$modeMenuItems){
    $item.ForeColor=$text;$item.BackColor=$surface
  }
  $cover.BackColor=$input
  $list.BackColor=$input;$list.ForeColor=$text
  if($list.IsHandleCreated){[PlayerDwm]::SetListTheme($list.Handle,$dark)}
  $list.Invalidate()
  foreach($label in @($now,$composerLabel,$albumLabel,$yearLabel,$clock,$volPercent)){
    $label.ForeColor=$text;$label.BackColor=$surface
  }
  $status.ForeColor=$muted;$status.BackColor=$surface
  foreach($buttonControl in @($prev,$play,$next,$stop,$muteButton)){
    $buttonControl.FlatStyle='Flat'
    $buttonControl.UseVisualStyleBackColor=$false
    $buttonControl.BackColor=$button
    $buttonControl.ForeColor=$text
    $buttonControl.FlatAppearance.BorderColor=$border
    $buttonControl.FlatAppearance.BorderSize=0
    $buttonControl.FlatAppearance.MouseOverBackColor=$hover
    $buttonControl.FlatAppearance.MouseDownBackColor=$hover
  }
  Update-TransportIcons
  foreach($slider in @($seek,$volume)){
    $slider.BackColor=$surface
    $slider.TrackColor=$track
    $slider.FillColor=$script:accent
    $slider.ThumbColor=$script:accent
    $slider.Invalidate()
  }
  if($script:playlistDialogContext){
    $ctx=$script:playlistDialogContext
    foreach($folderList in @($ctx.PresetList,$ctx.HistoryList)){
      $folderList.ActiveColor=$script:accent
      $folderList.SelectedColor=Blend-Color $folderList.BackColor $script:accent 0.24
      $folderList.Invalidate()
    }
    foreach($buttonControl in @($ctx.HeaderButtons)+$ctx.SwitchButtons){
      $buttonControl.FocusColor=$script:accent
      $buttonControl.Invalidate()
    }
  }
  if($form.IsHandleCreated){[PlayerDwm]::SetDarkTitleBar($form.Handle,$dark)}
}

function Shuffle-Bag {
  $script:bag.Clear()
  for($i=0;$i -lt $script:tracks.Count;$i++){
    if($script:tracks.Count -eq 1 -or $i -ne $script:current){$script:bag.Add($i)}
  }
  for($i=$script:bag.Count-1;$i -gt 0;$i--){
    $j=Get-Random -Minimum 0 -Maximum ($i+1)
    $t=$script:bag[$i];$script:bag[$i]=$script:bag[$j];$script:bag[$j]=$t
  }
}
function Reset-TrackInfo {
  $now.Text='尚未播放'
  $composerLabel.Text='作曲家：—'
  $albumLabel.Text='专辑：—'
  $yearLabel.Text='年份：—'
  foreach($label in @($now,$albumLabel)){$toolTip.SetToolTip($label,$label.Text)}
  $toolTip.SetToolTip($composerLabel,'—')
  $toolTip.SetToolTip($yearLabel,'—')
  $old=$cover.Image
  $cover.Image=$script:placeholderArt
  if($old -and -not [Object]::ReferenceEquals($old,$script:placeholderArt)){$old.Dispose()}
}
function Set-TrackInfo([string]$filePath) {
  $info=Get-SongInfo $filePath
  $now.Text=$info.Title
  $composerLabel.Text=$info.CreditLabel+'：'+$info.Composer
  $albumLabel.Text='专辑：'+$info.Album
  $yearLabel.Text='年份：'+$info.Year
  $toolTip.SetToolTip($now,$info.Title)
  $toolTip.SetToolTip($composerLabel,$info.Composer)
  $toolTip.SetToolTip($albumLabel,$info.Album)
  $toolTip.SetToolTip($yearLabel,$info.Year)
  $toolTip.SetToolTip($cover,$filePath)
  $newArt=$script:placeholderArt
  if($info.CoverBytes){
    $stream=$null;$sourceImage=$null;$graphics=$null;$image=$null
    try {
      $stream=[IO.MemoryStream]::new([byte[]]$info.CoverBytes)
      $sourceImage=[Drawing.Image]::FromStream($stream)
      $image=[Drawing.Bitmap]::new(144,144)
      $graphics=[Drawing.Graphics]::FromImage($image)
      $graphics.Clear($cover.BackColor)
      $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $ratio=[Math]::Min(144.0/$sourceImage.Width,144.0/$sourceImage.Height)
      $width=[int][Math]::Round($sourceImage.Width*$ratio)
      $height=[int][Math]::Round($sourceImage.Height*$ratio)
      $x=[int][Math]::Floor((144-$width)/2)
      $y=[int][Math]::Floor((144-$height)/2)
      $graphics.DrawImage($sourceImage,[Drawing.Rectangle]::new($x,$y,$width,$height))
      $newArt=$image
    }catch{
      if($image){$image.Dispose()}
    }finally{
      if($graphics){$graphics.Dispose()}
      if($sourceImage){$sourceImage.Dispose()}
      if($stream){$stream.Dispose()}
    }
  }
  $old=$cover.Image
  $cover.Image=$newArt
  if($old -and -not [Object]::ReferenceEquals($old,$script:placeholderArt) -and
     -not [Object]::ReferenceEquals($old,$newArt)){$old.Dispose()}
}
function Start-Track([int]$index,[bool]$remember=$true){
  if($index -lt 0 -or $index -ge $script:tracks.Count){return}
  try{
    $script:player.Stop();$script:player.Close()
    $script:player.Open([Uri]::new($script:tracks[$index].FullName))
    Apply-Volume
    $script:player.Play()
    $script:current=$index;$script:playing=$true;$script:paused=$false
    Update-TransportIcons;Update-TaskbarProgress
    $status.Text='正在播放  |  '+$script:tracks[$index].Name
    Set-TrackInfo $script:tracks[$index].FullName
    $list.SelectedItems.Clear()
    $list.Items[$index].Selected=$true
    $list.Items[$index].EnsureVisible()
    [void]$script:bag.Remove($index)
    if($remember){
      while($script:history.Count -gt ($script:historyPos+1)){
        $script:history.RemoveAt($script:history.Count-1)
      }
      $script:history.Add($index);$script:historyPos=$script:history.Count-1
    }
  }catch{$script:playing=$false;$script:paused=$false;Update-TransportIcons;Update-TaskbarProgress;$status.Text='无法播放：'+$_.Exception.Message}
}

function Finish-Playback([bool]$listFinished=$false) {
  $script:player.Stop()
  $script:playing=$false
  $script:paused=$false
  Update-TransportIcons
  Update-TaskbarProgress
  $clock.Text='00:00'
  $seek.Value=0
  if($listFinished){
    $script:current=-1
    $now.Text='列表播放完成'
    $status.Text='列表已播放一遍。再次点击播放会从第一首开始。'
  }else{
    $status.Text='当前曲目已播放一遍。'
  }
}
function Play-Next([bool]$automatic=$false) {
  if($script:tracks.Count -eq 0){return}
  if($script:current -lt 0 -and $script:mode -ne 'random'){
    Start-Track 0
    return
  }
  if($automatic -and $script:mode -eq 'single-once'){
    Finish-Playback
    return
  }
  if($automatic -and $script:mode -eq 'single-loop'){
    Start-Track $script:current $false
    return
  }
  if($script:mode -eq 'random'){
    if($script:bag.Count -eq 0){Shuffle-Bag}
    if($script:bag.Count -eq 0){return}
    $index=$script:bag[0]
    $script:bag.RemoveAt(0)
    Start-Track $index
    return
  }
  $index=$script:current+1
  if($index -ge $script:tracks.Count){
    if($script:mode -eq 'list-once'){
      Finish-Playback $true
      return
    }
    $index=0
  }
  Start-Track $index
}
function Play-Previous {
  if($script:tracks.Count -eq 0){return}
  if($script:mode -eq 'random'){
    if($script:historyPos -gt 0){
      $script:historyPos--
      Start-Track $script:history[$script:historyPos] $false
    }elseif($script:current -ge 0){$script:player.Position=[TimeSpan]::Zero}
    return
  }
  if($script:current -gt 0){
    Start-Track ($script:current-1)
  }elseif($script:current -ge 0){
    $script:player.Position=[TimeSpan]::Zero
  }
}
function Scan-Folder {
  $script:player.Stop();$script:player.Close()
  $script:current=-1;$script:playing=$false;$script:paused=$false
  $script:bag.Clear();$script:history.Clear();$script:historyPos=-1
  Update-TransportIcons;Update-TaskbarProgress;$clock.Text='00:00 / 00:00';$seek.Value=0
  Reset-TrackInfo
  $script:tracks=@()
  $list.BeginUpdate()
  $list.Items.Clear()
  try {
    if(Test-Path -LiteralPath $script:path -PathType Container){
      $script:tracks=@(Get-ChildItem -LiteralPath $script:path -File -Recurse -ErrorAction SilentlyContinue|
        Where-Object {$extensions -contains $_.Extension.ToLowerInvariant()}|Sort-Object FullName)
      for($i=0;$i -lt $script:tracks.Count;$i++){
        $relative=$script:tracks[$i].FullName.Substring($script:path.TrimEnd('\').Length).TrimStart('\')
        $item=[Windows.Forms.ListViewItem]::new([string]($i+1))
        [void]$item.SubItems.Add($relative)
        [void]$list.Items.Add($item)
      }
      $status.Text="已载入 $($script:tracks.Count) 首音乐  |  $script:path"
    }else{$status.Text='目录不存在，请从“文件”菜单选择音乐目录。'}
  }catch{$status.Text='扫描失败：'+$_.Exception.Message}
  finally{$list.EndUpdate()}
  $toolTip.SetToolTip($status,$script:path)
  Save-Config
}
function Set-MusicFolder([string]$candidate) {
  $normalized=Normalize-FolderPath $candidate
  if(-not $normalized -or -not [IO.Directory]::Exists($normalized)){
    [void][Windows.Forms.MessageBox]::Show($form,"目录不存在：$candidate",'无法切换目录')
    return $false
  }
  $script:path=$normalized
  Record-RecentFolder $normalized
  Scan-Folder
  return $true
}
$chooseAction={
  $initial=$script:path
  try {
    $selected=[ModernFolderPicker]::Pick($form.Handle,$initial)
  } catch {
    $dialog=[Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description='选择音乐目录（包括子目录）'
    if([IO.Directory]::Exists($initial)){$dialog.SelectedPath=$initial}
    $selected=$null
    if($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$selected=$dialog.SelectedPath}
    $dialog.Dispose()
  }
  if($selected){[void](Set-MusicFolder $selected)}
}
$chooseMenu.Add_Click($chooseAction)
$addressMenu.Add_Click({
  $addressDialog=[Windows.Forms.Form]::new()
  $addressDialog.Text='输入音乐目录地址'
  $addressDialog.Size=[Drawing.Size]::new(560,180)
  $addressDialog.StartPosition='CenterParent'
  $addressDialog.FormBorderStyle='FixedDialog'
  $addressDialog.MaximizeBox=$false;$addressDialog.MinimizeBox=$false
  $addressDialog.ShowInTaskbar=$false;$addressDialog.Font=$form.Font
  $prompt=[Windows.Forms.Label]::new()
  $prompt.Text='输入或粘贴音乐目录路径：'
  $prompt.Location=[Drawing.Point]::new(16,14);$prompt.Size=[Drawing.Size]::new(510,25)
  $entry=[Windows.Forms.TextBox]::new()
  $entry.Text=$script:path
  $entry.Location=[Drawing.Point]::new(16,43);$entry.Size=[Drawing.Size]::new(510,30)
  $accept=[Windows.Forms.Button]::new();$accept.Text='使用此目录'
  $accept.Location=[Drawing.Point]::new(320,87);$accept.Size=[Drawing.Size]::new(110,34)
  $accept.DialogResult='OK'
  $cancel=[Windows.Forms.Button]::new();$cancel.Text='取消'
  $cancel.Location=[Drawing.Point]::new(440,87);$cancel.Size=[Drawing.Size]::new(86,34)
  $cancel.DialogResult='Cancel'
  $addressDialog.AcceptButton=$accept;$addressDialog.CancelButton=$cancel
  [void]$addressDialog.Controls.AddRange([Windows.Forms.Control[]]@($prompt,$entry,$accept,$cancel))
  if($script:themeDark){
    $surface=[Drawing.Color]::FromArgb(30,32,36)
    $text=[Drawing.Color]::FromArgb(238,239,242)
    $addressDialog.BackColor=$surface
    $prompt.ForeColor=$text
    $entry.BackColor=[Drawing.Color]::FromArgb(42,44,49);$entry.ForeColor=$text
    foreach($buttonControl in @($accept,$cancel)){
      $buttonControl.FlatStyle='Flat';$buttonControl.BackColor=[Drawing.Color]::FromArgb(53,56,62)
      $buttonControl.ForeColor=$text
    }
    $addressDialog.Add_Shown({[PlayerDwm]::SetDarkTitleBar($addressDialog.Handle,$true)})
  }
  $entry.SelectAll()
  if($addressDialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){
    $candidate=[Environment]::ExpandEnvironmentVariables($entry.Text.Trim().Trim('"'))
    [void](Set-MusicFolder $candidate)
  }
  $addressDialog.Dispose()
})
function Prompt-PresetFolder([string]$initial,[string]$title,[Windows.Forms.Form]$owner) {
  $dialog=[Windows.Forms.Form]::new()
  $dialog.Text=$title
  $dialog.ClientSize=[Drawing.Size]::new(620,154)
  $dialog.StartPosition='CenterParent'
  $dialog.FormBorderStyle='FixedDialog'
  $dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false
  $dialog.ShowInTaskbar=$false;$dialog.Font=$form.Font
  if($form.Icon){$dialog.Icon=$form.Icon}
  $dark=[bool]$script:themeDark
  $surface=if($dark){[Drawing.Color]::FromArgb(30,32,36)}else{[Drawing.Color]::FromArgb(248,248,248)}
  $textColor=if($dark){[Drawing.Color]::FromArgb(238,239,242)}else{[Drawing.Color]::FromArgb(25,27,30)}
  $fieldColor=if($dark){[Drawing.Color]::FromArgb(42,44,49)}else{[Drawing.Color]::White}
  $buttonColor=if($dark){[Drawing.Color]::FromArgb(53,56,62)}else{[Drawing.Color]::FromArgb(240,240,240)}
  $dialog.BackColor=$surface;$dialog.ForeColor=$textColor
  $prompt=[Windows.Forms.Label]::new()
  $prompt.Text='输入目录地址，或点击右侧按钮选择文件夹：'
  $prompt.Location=[Drawing.Point]::new(16,15);$prompt.Size=[Drawing.Size]::new(570,24)
  $entry=[Windows.Forms.TextBox]::new()
  $entry.Text=$initial
  $entry.Location=[Drawing.Point]::new(16,43);$entry.Size=[Drawing.Size]::new(515,29)
  $entry.BackColor=$fieldColor;$entry.ForeColor=$textColor
  $dialog.Tag=[pscustomobject]@{Entry=$entry;Dark=$dark}
  $browse=[Windows.Forms.Button]::new()
  $browse.Text='…';$browse.AccessibleName='浏览文件夹'
  $browse.Location=[Drawing.Point]::new(540,42);$browse.Size=[Drawing.Size]::new(62,30)
  $browse.Add_Click({
    param($sender,$e)
    $pickerDialog=$sender.FindForm()
    $pickerEntry=$pickerDialog.Tag.Entry
    $start=Normalize-FolderPath $pickerEntry.Text
    if(-not $start -or -not [IO.Directory]::Exists($start)){$start=$script:path}
    try{$picked=[ModernFolderPicker]::Pick($pickerDialog.Handle,$start)}
    catch{
      $fallback=[Windows.Forms.FolderBrowserDialog]::new()
      $fallback.Description='选择音乐目录'
      if([IO.Directory]::Exists($start)){$fallback.SelectedPath=$start}
      $picked=$null
      if($fallback.ShowDialog($pickerDialog) -eq [Windows.Forms.DialogResult]::OK){$picked=$fallback.SelectedPath}
      $fallback.Dispose()
    }
    if($picked){$pickerEntry.Text=$picked}
  })
  $ok=[Windows.Forms.Button]::new()
  $ok.Text='确定';$ok.Location=[Drawing.Point]::new(398,96);$ok.Size=[Drawing.Size]::new(98,34)
  $ok.DialogResult='OK'
  $cancel=[Windows.Forms.Button]::new()
  $cancel.Text='取消';$cancel.Location=[Drawing.Point]::new(504,96);$cancel.Size=[Drawing.Size]::new(98,34)
  $cancel.DialogResult='Cancel'
  foreach($buttonControl in @($browse,$ok,$cancel)){
    $buttonControl.FlatStyle='Flat';$buttonControl.UseVisualStyleBackColor=$false
    $buttonControl.BackColor=$buttonColor;$buttonControl.ForeColor=$textColor
  }
  $dialog.AcceptButton=$ok;$dialog.CancelButton=$cancel
  [void]$dialog.Controls.AddRange([Windows.Forms.Control[]]@($prompt,$entry,$browse,$ok,$cancel))
  $dialog.Add_HandleCreated({param($sender,$e)
    [PlayerDwm]::SetDarkTitleBar($sender.Handle,[bool]$sender.Tag.Dark)
  })
  $dialog.Add_Shown({param($sender,$e)
    [PlayerDwm]::SetDarkTitleBar($sender.Handle,[bool]$sender.Tag.Dark)
    $sender.Tag.Entry.Focus();$sender.Tag.Entry.SelectAll()
  })
  $result=$null
  try{
    if($dialog.ShowDialog($owner) -eq [Windows.Forms.DialogResult]::OK){
      $result=Normalize-FolderPath $entry.Text
      if(-not $result -or -not [IO.Directory]::Exists($result)){
        [void][Windows.Forms.MessageBox]::Show($owner,"目录不存在：$($entry.Text)",'无效的文件夹')
        $result=$null
      }
    }
  }finally{$dialog.Dispose()}
  return $result
}
function Confirm-DeletePreset([string]$folder,[Windows.Forms.Form]$owner) {
  $dialog=[Windows.Forms.Form]::new()
  $dialog.Text='确认删除预设'
  $dialog.ClientSize=[Drawing.Size]::new(450,170)
  $dialog.StartPosition='CenterParent'
  $dialog.FormBorderStyle='FixedDialog'
  $dialog.MaximizeBox=$false;$dialog.MinimizeBox=$false
  $dialog.ShowInTaskbar=$false;$dialog.Font=$form.Font
  if($form.Icon){$dialog.Icon=$form.Icon}
  $dark=[bool]$script:themeDark
  $surface=if($dark){[Drawing.Color]::FromArgb(30,32,36)}else{[Drawing.Color]::FromArgb(248,248,248)}
  $textColor=if($dark){[Drawing.Color]::FromArgb(238,239,242)}else{[Drawing.Color]::FromArgb(25,27,30)}
  $mutedColor=if($dark){[Drawing.Color]::FromArgb(181,185,193)}else{[Drawing.Color]::FromArgb(85,85,85)}
  $buttonColor=if($dark){[Drawing.Color]::FromArgb(53,56,62)}else{[Drawing.Color]::FromArgb(235,235,235)}
  $dialog.BackColor=$surface;$dialog.ForeColor=$textColor
  $dialog.Tag=[pscustomobject]@{Dark=$dark;Border=$surface}
  $question=[Windows.Forms.Label]::new()
  $question.Text='从“我的播放列表”中删除这个文件夹预设？'
  $question.Location=[Drawing.Point]::new(18,20);$question.Size=[Drawing.Size]::new(410,30)
  $question.ForeColor=$textColor
  $pathLabel=[Windows.Forms.Label]::new()
  $pathLabel.Text=$folder;$pathLabel.AutoEllipsis=$true
  $pathLabel.Location=[Drawing.Point]::new(18,58);$pathLabel.Size=[Drawing.Size]::new(410,28)
  $pathLabel.ForeColor=$mutedColor
  $cancel=[ThemedPlaylistButton]::new()
  $cancel.Text='取消';$cancel.DialogResult=[Windows.Forms.DialogResult]::Cancel
  $cancel.Location=[Drawing.Point]::new(332,112);$cancel.Size=[Drawing.Size]::new(100,36)
  $cancel.BackColor=$buttonColor;$cancel.ForeColor=$textColor
  $delete=[ThemedPlaylistButton]::new()
  $delete.Text='删除预设';$delete.DialogResult=[Windows.Forms.DialogResult]::Yes
  $delete.Location=[Drawing.Point]::new(216,112);$delete.Size=[Drawing.Size]::new(108,36)
  $delete.BackColor=if($dark){[Drawing.Color]::FromArgb(94,51,55)}else{[Drawing.Color]::FromArgb(245,217,219)}
  $delete.ForeColor=$textColor
  $delete.HoverColor=if($dark){[Drawing.Color]::FromArgb(111,61,66)}else{[Drawing.Color]::FromArgb(237,197,201)}
  $dialog.CancelButton=$cancel
  [void]$dialog.Controls.AddRange([Windows.Forms.Control[]]@($question,$pathLabel,$delete,$cancel))
  $dialog.Add_HandleCreated({param($sender,$e)
    [PlayerDwm]::SetDarkTitleBar($sender.Handle,[bool]$sender.Tag.Dark)
    [PlayerDwm]::SetBorderColor($sender.Handle,$sender.Tag.Border)
  })
  try{return ($dialog.ShowDialog($owner) -eq [Windows.Forms.DialogResult]::Yes)}
  finally{$dialog.Dispose()}
}
function New-FolderActionButton([int]$kind,[string]$name,[Drawing.Color]$color,[Drawing.Color]$background) {
  $button=[Windows.Forms.Button]::new()
  $button.Size=[Drawing.Size]::new(36,34)
  $button.Margin=[Windows.Forms.Padding]::new(0,1,8,0)
  $button.Image=[FolderActionGlyphs]::CreateBitmap($kind,$color)
  $button.ImageAlign='MiddleCenter'
  $button.AccessibleName=$name
  $button.FlatStyle='Flat';$button.UseVisualStyleBackColor=$false
  $button.FlatAppearance.BorderSize=0
  $button.BackColor=$background;$button.ForeColor=$color
  return $button
}
function Select-PlaylistPage([int]$index) {
  $ctx=$script:playlistDialogContext
  if(-not $ctx){return}
  for($i=0;$i -lt 2;$i++){
    $selected=($i -eq $index)
    $ctx.PagePanels[$i].Visible=$selected
    $ctx.HeaderButtons[$i].BackColor=if($selected){$ctx.InputColor}else{$ctx.SurfaceColor}
    $ctx.HeaderButtons[$i].Invalidate()
  }
  $ctx.PagePanels[$index].BringToFront()
}
function Show-PlaylistWindow {
  $window=[Windows.Forms.Form]::new()
  $window.Text='播放列表'
  $window.ClientSize=[Drawing.Size]::new(760,520)
  $window.MinimumSize=[Drawing.Size]::new(610,400)
  $window.StartPosition='CenterParent'
  $window.ShowInTaskbar=$false
  $window.Font=$form.Font
  if($form.Icon){$window.Icon=$form.Icon}
  $dark=[bool]$script:themeDark
  $surface=if($dark){[Drawing.Color]::FromArgb(30,32,36)}else{[Drawing.Color]::FromArgb(248,248,248)}
  $input=if($dark){[Drawing.Color]::FromArgb(42,44,49)}else{[Drawing.Color]::White}
  $buttonColor=if($dark){[Drawing.Color]::FromArgb(53,56,62)}else{[Drawing.Color]::FromArgb(240,240,240)}
  $textColor=if($dark){[Drawing.Color]::FromArgb(238,239,242)}else{[Drawing.Color]::FromArgb(25,27,30)}
  $mutedColor=if($dark){[Drawing.Color]::FromArgb(181,185,193)}else{[Drawing.Color]::FromArgb(90,90,90)}
  $selectedColor=Blend-Color $input $script:accent $(if($dark){0.24}else{0.18})
  $lineColor=if($dark){[Drawing.Color]::FromArgb(68,72,79)}else{[Drawing.Color]::FromArgb(218,221,226)}
  $window.BackColor=$surface;$window.ForeColor=$textColor
  $shell=[Windows.Forms.TableLayoutPanel]::new()
  $shell.Dock='Fill';$shell.ColumnCount=1;$shell.RowCount=2
  $shell.Margin=[Windows.Forms.Padding]::new(0)
  [void]$shell.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',38))
  [void]$shell.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
  $shell.BackColor=$surface
  $tabHeader=[Windows.Forms.FlowLayoutPanel]::new()
  $tabHeader.Dock='Fill';$tabHeader.WrapContents=$false
  $tabHeader.Margin=[Windows.Forms.Padding]::new(0)
  $tabHeader.BackColor=$surface
  $tabButtons=@()
  foreach($title in @('我的播放列表','历史播放列表')){
    $tabButton=[ThemedPlaylistButton]::new()
    $tabButton.Text=$title;$tabButton.Size=[Drawing.Size]::new(154,36)
    $tabButton.Margin=[Windows.Forms.Padding]::new(0)
    $tabButton.BackColor=$surface;$tabButton.ForeColor=$textColor
    $tabButton.HoverColor=$buttonColor;$tabButton.PressedColor=$input
    $tabButton.FocusColor=$script:accent
    [void]$tabHeader.Controls.Add($tabButton)
    $tabButtons+=,$tabButton
  }
  $tabButtons[0].BackColor=$input
  $pageHost=[Windows.Forms.Panel]::new()
  $pageHost.Dock='Fill';$pageHost.Margin=[Windows.Forms.Padding]::new(0)
  $pageHost.BackColor=$surface
  $presetPage=[Windows.Forms.Panel]::new()
  $historyPage=[Windows.Forms.Panel]::new()
  foreach($page in @($presetPage,$historyPage)){
    $page.Dock='Fill';$page.BackColor=$surface;$page.ForeColor=$textColor
    [void]$pageHost.Controls.Add($page)
  }
  $historyPage.Visible=$false
  [void]$shell.Controls.Add($tabHeader,0,0)
  [void]$shell.Controls.Add($pageHost,0,1)
  [void]$window.Controls.Add($shell)
  $playlistToolTip=[Windows.Forms.ToolTip]::new()
  $layouts=@()
  foreach($page in @($presetPage,$historyPage)){
    $layout=[Windows.Forms.TableLayoutPanel]::new()
    $layout.Dock='Fill';$layout.ColumnCount=1;$layout.RowCount=3
    $layout.Padding=[Windows.Forms.Padding]::new(10,12,10,8)
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',42))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Percent',100))
    [void]$layout.RowStyles.Add([Windows.Forms.RowStyle]::new('Absolute',52))
    $layout.BackColor=$surface
    [void]$page.Controls.Add($layout)
    $layouts+=,$layout
  }
  $presetToolbar=[Windows.Forms.FlowLayoutPanel]::new()
  $presetToolbar.Dock='Fill';$presetToolbar.WrapContents=$false
  $presetToolbar.BackColor=$surface
  $addButton=New-FolderActionButton 0 '添加文件夹' $textColor $buttonColor
  $deleteButton=New-FolderActionButton 1 '删除预设' $textColor $buttonColor
  $editButton=New-FolderActionButton 2 '修改目录' $textColor $buttonColor
  foreach($control in @($addButton,$deleteButton,$editButton)){
    [void]$presetToolbar.Controls.Add($control)
    $playlistToolTip.SetToolTip($control,$control.AccessibleName)
  }
  $dragHint=[Windows.Forms.Label]::new()
  $dragHint.Text='拖动项目可调整顺序';$dragHint.AutoSize=$true
  $dragHint.ForeColor=$mutedColor;$dragHint.Margin=[Windows.Forms.Padding]::new(10,9,0,0)
  [void]$presetToolbar.Controls.Add($dragHint)
  [void]$layouts[0].Controls.Add($presetToolbar,0,0)
  $historyToolbar=[Windows.Forms.FlowLayoutPanel]::new()
  $historyToolbar.Dock='Fill';$historyToolbar.WrapContents=$false
  $historyToolbar.BackColor=$surface
  $deleteHistoryButton=New-FolderActionButton 1 '删除历史记录' $textColor $buttonColor
  [void]$historyToolbar.Controls.Add($deleteHistoryButton)
  $playlistToolTip.SetToolTip($deleteHistoryButton,'删除历史记录')
  $historyHint=[Windows.Forms.Label]::new()
  $historyHint.Text='最近使用的目录，最多 64 条';$historyHint.AutoSize=$true
  $historyHint.ForeColor=$mutedColor;$historyHint.Margin=[Windows.Forms.Padding]::new(10,9,0,0)
  [void]$historyToolbar.Controls.Add($historyHint)
  [void]$layouts[1].Controls.Add($historyToolbar,0,0)
  $presetList=[FolderPresetList]::new()
  $presetList.Dock='Fill';$presetList.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
  $presetList.BackColor=$input;$presetList.ForeColor=$textColor
  $presetList.MutedColor=$mutedColor;$presetList.SelectedColor=$selectedColor
  $presetList.LineColor=$lineColor;$presetList.ActiveColor=$script:accent
  $presetList.ActivePath=$script:path
  $presetList.Add_HandleCreated({param($sender,$e)
    [PlayerDwm]::SetListTheme($sender.Handle,[bool]$script:themeDark)
  })
  $presetList.SetPaths($script:presets.ToArray())
  [void]$layouts[0].Controls.Add($presetList,0,1)
  $historyList=[FolderPresetList]::new()
  $historyList.Dock='Fill';$historyList.Margin=[Windows.Forms.Padding]::new(0,0,0,0)
  $historyList.BackColor=$input;$historyList.ForeColor=$textColor
  $historyList.MutedColor=$mutedColor;$historyList.SelectedColor=$selectedColor
  $historyList.LineColor=$lineColor;$historyList.ActiveColor=$script:accent
  $historyList.ReorderEnabled=$false;$historyList.ActivePath=$script:path
  $historyList.Add_HandleCreated({param($sender,$e)
    [PlayerDwm]::SetListTheme($sender.Handle,[bool]$script:themeDark)
  })
  $historyList.SetPaths($script:recentFolders.ToArray())
  [void]$layouts[1].Controls.Add($historyList,0,1)
  $footers=@()
  $switchButtons=@()
  $countLabels=@()
  for($i=0;$i -lt 2;$i++){
    $footer=[Windows.Forms.TableLayoutPanel]::new()
    $footer.Dock='Fill';$footer.ColumnCount=2;$footer.RowCount=1
    [void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Percent',100))
    [void]$footer.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new('Absolute',160))
    $footer.BackColor=$surface
    $count=[Windows.Forms.Label]::new()
    $count.Dock='Fill';$count.TextAlign='MiddleLeft';$count.ForeColor=$mutedColor
    $count.Text=if($i -eq 0){"共 $($script:presets.Count) 个预设"}else{"共 $($script:recentFolders.Count) 条记录"}
    [void]$footer.Controls.Add($count,0,0)
    $switch=[ThemedPlaylistButton]::new()
    $switch.Text='切换到此目录';$switch.Dock='Fill'
    $switch.Margin=[Windows.Forms.Padding]::new(0,8,0,7)
    $switch.BackColor=$buttonColor;$switch.ForeColor=$textColor
    $switch.DisabledBackColor=if($dark){[Drawing.Color]::FromArgb(43,45,49)}else{[Drawing.Color]::FromArgb(232,232,232)}
    $switch.DisabledForeColor=if($dark){[Drawing.Color]::FromArgb(139,144,152)}else{[Drawing.Color]::FromArgb(125,125,125)}
    $switch.HoverColor=if($dark){[Drawing.Color]::FromArgb(68,72,79)}else{[Drawing.Color]::FromArgb(226,234,244)}
    $switch.PressedColor=if($dark){[Drawing.Color]::FromArgb(76,80,88)}else{[Drawing.Color]::FromArgb(212,224,238)}
    $switch.FocusColor=$script:accent
    $switch.Enabled=$false
    [void]$footer.Controls.Add($switch,1,0)
    [void]$layouts[$i].Controls.Add($footer,0,2)
    $footers+=,$footer;$switchButtons+=,$switch;$countLabels+=,$count
  }
  $script:playlistDialogContext=[pscustomobject]@{
    Window=$window;PresetList=$presetList;HistoryList=$historyList
    AddButton=$addButton;DeleteButton=$deleteButton;EditButton=$editButton
    DeleteHistoryButton=$deleteHistoryButton;SwitchButtons=$switchButtons
    CountLabels=$countLabels;Dark=$dark;PagePanels=@($presetPage,$historyPage)
    HeaderButtons=$tabButtons;SurfaceColor=$surface;InputColor=$input
  }
  $tabButtons[0].Add_Click({Select-PlaylistPage 0})
  $tabButtons[1].Add_Click({Select-PlaylistPage 1})
  $presetList.Add_SelectionChanged({
    $ctx=$script:playlistDialogContext
    $hasSelection=($null -ne $ctx.PresetList.SelectedPath)
    $ctx.DeleteButton.Enabled=$hasSelection;$ctx.EditButton.Enabled=$hasSelection
    $ctx.SwitchButtons[0].Enabled=$hasSelection
  })
  $historyList.Add_SelectionChanged({
    $ctx=$script:playlistDialogContext
    $hasSelection=($null -ne $ctx.HistoryList.SelectedPath)
    $ctx.DeleteHistoryButton.Enabled=$hasSelection;$ctx.SwitchButtons[1].Enabled=$hasSelection
  })
  $deleteButton.Enabled=$false;$editButton.Enabled=$false;$deleteHistoryButton.Enabled=$false
  $addButton.Add_Click({
    $ctx=$script:playlistDialogContext
    $chosen=Prompt-PresetFolder $script:path '添加播放列表文件夹' $ctx.Window
    if(-not $chosen){return}
    if((Find-FolderIndex $script:presets $chosen) -lt 0){$script:presets.Add($chosen);Save-Config}
    $ctx.PresetList.SetPaths($script:presets.ToArray())
    $ctx.PresetList.SelectPath($chosen)
    $ctx.CountLabels[0].Text="共 $($script:presets.Count) 个预设"
  })
  $deleteButton.Add_Click({
    $ctx=$script:playlistDialogContext
    $selected=$ctx.PresetList.SelectedPath
    if(-not $selected){return}
    if(-not (Confirm-DeletePreset $selected $ctx.Window)){return}
    $index=Find-FolderIndex $script:presets $selected
    if($index -ge 0){$script:presets.RemoveAt($index);Save-Config}
    $ctx.PresetList.SetPaths($script:presets.ToArray())
    $ctx.CountLabels[0].Text="共 $($script:presets.Count) 个预设"
  })
  $editButton.Add_Click({
    $ctx=$script:playlistDialogContext
    $previous=$ctx.PresetList.SelectedPath
    if(-not $previous){return}
    $chosen=Prompt-PresetFolder $previous '修改播放列表文件夹' $ctx.Window
    if(-not $chosen){return}
    $index=Find-FolderIndex $script:presets $previous
    if($index -lt 0){return}
    $duplicate=Find-FolderIndex $script:presets $chosen
    if($duplicate -ge 0 -and $duplicate -ne $index){
      [void][Windows.Forms.MessageBox]::Show($ctx.Window,'该目录已在我的播放列表中。','无法重复添加')
      return
    }
    $script:presets[$index]=$chosen
    Save-Config
    $ctx.PresetList.SetPaths($script:presets.ToArray())
    $ctx.PresetList.SelectPath($chosen)
    if([string]::Equals($script:path,$previous,[StringComparison]::OrdinalIgnoreCase)){
      [void](Set-MusicFolder $chosen)
      $ctx.PresetList.ActivePath=$script:path;$ctx.HistoryList.ActivePath=$script:path
      $ctx.PresetList.Invalidate();$ctx.HistoryList.Invalidate()
      $ctx.HistoryList.SetPaths($script:recentFolders.ToArray())
      $ctx.CountLabels[1].Text="共 $($script:recentFolders.Count) 条记录"
    }
  })
  $presetList.Add_OrderChanged({
    $ctx=$script:playlistDialogContext
    $script:presets.Clear()
    foreach($path in $ctx.PresetList.Paths){$script:presets.Add($path)}
    Save-Config
  })
  $deleteHistoryButton.Add_Click({
    $ctx=$script:playlistDialogContext
    $selected=$ctx.HistoryList.SelectedPath
    if(-not $selected){return}
    $index=Find-FolderIndex $script:recentFolders $selected
    if($index -ge 0){$script:recentFolders.RemoveAt($index);Save-Config}
    $ctx.HistoryList.SetPaths($script:recentFolders.ToArray())
    $ctx.CountLabels[1].Text="共 $($script:recentFolders.Count) 条记录"
  })
  $activatePreset={
    $ctx=$script:playlistDialogContext
    if($ctx.PresetList.SelectedPath -and (Set-MusicFolder $ctx.PresetList.SelectedPath)){$ctx.Window.Close()}
  }
  $activateHistory={
    $ctx=$script:playlistDialogContext
    if($ctx.HistoryList.SelectedPath -and (Set-MusicFolder $ctx.HistoryList.SelectedPath)){$ctx.Window.Close()}
  }
  $switchButtons[0].Add_Click($activatePreset)
  $switchButtons[1].Add_Click($activateHistory)
  $presetList.Add_ItemActivated($activatePreset)
  $historyList.Add_ItemActivated($activateHistory)
  $presetList.Add_KeyDown({param($sender,$e)
    if($e.KeyCode -eq [Windows.Forms.Keys]::Delete){$script:playlistDialogContext.DeleteButton.PerformClick();$e.Handled=$true}
  })
  $historyList.Add_KeyDown({param($sender,$e)
    if($e.KeyCode -eq [Windows.Forms.Keys]::Delete){$script:playlistDialogContext.DeleteHistoryButton.PerformClick();$e.Handled=$true}
  })
  $window.Add_HandleCreated({param($sender,$e)
    [PlayerDwm]::SetDarkTitleBar($sender.Handle,[bool]$script:playlistDialogContext.Dark)
    [PlayerDwm]::SetBorderColor($sender.Handle,$script:playlistDialogContext.SurfaceColor)
  })
  $window.Add_Shown({param($sender,$e)
    [PlayerDwm]::SetDarkTitleBar($sender.Handle,[bool]$script:playlistDialogContext.Dark)
    [PlayerDwm]::SetBorderColor($sender.Handle,$script:playlistDialogContext.SurfaceColor)
  })
  try{[void]$window.ShowDialog($form)}
  finally{
    $script:playlistDialogContext=$null
    foreach($button in @($addButton,$deleteButton,$editButton,$deleteHistoryButton)){
      if($button.Image){$button.Image.Dispose();$button.Image=$null}
    }
    $playlistToolTip.Dispose();$window.Dispose()
  }
}
$playlistMenu.Add_Click({Show-PlaylistWindow})
$rescanMenu.Add_Click({Scan-Folder})
$exitMenu.Add_Click({$form.Close()})
function Show-About {
  $about=[Windows.Forms.Form]::new()
  $about.Text='关于 LocalMusicPlayer'
  $about.ClientSize=[Drawing.Size]::new(660,500)
  $about.StartPosition='CenterParent'
  $about.FormBorderStyle='FixedDialog'
  $about.MaximizeBox=$false;$about.MinimizeBox=$false
  $about.ShowInTaskbar=$false;$about.Font=$form.Font
  if($form.Icon){$about.Icon=$form.Icon}
  $dark=[bool]$script:themeDark
  $surface=if($dark){[Drawing.Color]::FromArgb(30,32,36)}else{[Drawing.Color]::FromArgb(248,248,248)}
  $panelColor=if($dark){[Drawing.Color]::FromArgb(39,41,46)}else{[Drawing.Color]::White}
  $textColor=if($dark){[Drawing.Color]::FromArgb(238,239,242)}else{[Drawing.Color]::FromArgb(25,27,30)}
  $mutedColor=if($dark){[Drawing.Color]::FromArgb(181,185,193)}else{[Drawing.Color]::FromArgb(85,85,85)}
  $about.BackColor=$surface;$about.ForeColor=$textColor
  $logo=[Windows.Forms.PictureBox]::new()
  $logo.Location=[Drawing.Point]::new(24,22);$logo.Size=[Drawing.Size]::new(58,58)
  $logo.SizeMode='Zoom'
  if($form.Icon){$logo.Image=$form.Icon.ToBitmap()}
  [void]$about.Controls.Add($logo)
  $title=[Windows.Forms.Label]::new()
  $title.Text='LocalMusicPlayer';$title.Location=[Drawing.Point]::new(104,19)
  $title.Size=[Drawing.Size]::new(530,37)
  $title.Font=[Drawing.Font]::new('Microsoft YaHei UI',15,[Drawing.FontStyle]::Bold)
  $title.ForeColor=$textColor
  [void]$about.Controls.Add($title)
  $author=[Windows.Forms.Label]::new()
  $author.Text='世界重构 · FlashDragon · 庚辰'
  $author.Location=[Drawing.Point]::new(105,58);$author.Size=[Drawing.Size]::new(525,28)
  $author.ForeColor=$mutedColor
  [void]$about.Controls.Add($author)
  $summary=[Windows.Forms.Label]::new()
  $summary.Text='轻量的本地音乐播放器，支持多种播放模式与媒体标签。'
  $summary.Location=[Drawing.Point]::new(22,104);$summary.Size=[Drawing.Size]::new(610,28)
  $summary.ForeColor=$textColor
  [void]$about.Controls.Add($summary)
  $build=[Windows.Forms.GroupBox]::new()
  $build.Text='构建信息';$build.Location=[Drawing.Point]::new(20,140)
  $build.Size=[Drawing.Size]::new(620,102);$build.ForeColor=$textColor;$build.BackColor=$surface
  [void]$about.Controls.Add($build)
  $details=@(
    @('版本','1.0.0.2'),
    @('程序许可','MIT'),
    @('媒体标签组件','TagLibSharp 2.3.0 · LGPL-2.1-only')
  )
  for($i=0;$i -lt $details.Count;$i++){
    $caption=[Windows.Forms.Label]::new()
    $caption.Text=$details[$i][0]+'：';$caption.Location=[Drawing.Point]::new(16,23+24*$i)
    $caption.Size=[Drawing.Size]::new(122,23);$caption.ForeColor=$mutedColor
    [void]$build.Controls.Add($caption)
    $value=[Windows.Forms.Label]::new()
    $value.Text=$details[$i][1];$value.Location=[Drawing.Point]::new(145,23+24*$i)
    $value.Size=[Drawing.Size]::new(455,23);$value.ForeColor=$textColor
    [void]$build.Controls.Add($value)
  }
  $contacts=[Windows.Forms.GroupBox]::new()
  $contacts.Text='项目与作者';$contacts.Location=[Drawing.Point]::new(20,254)
  $contacts.Size=[Drawing.Size]::new(620,160)
  $contacts.ForeColor=$textColor;$contacts.BackColor=$surface
  [void]$about.Controls.Add($contacts)
  $links=@(
    [pscustomobject]@{Name='GitHub 仓库';Address='github.com/FlashDragons/LocalMusicPlayer';Url='https://github.com/FlashDragons/LocalMusicPlayer'},
    [pscustomobject]@{Name='个人网站';Address='flashdragons.github.io';Url='https://flashdragons.github.io'},
    [pscustomobject]@{Name='哔哩哔哩';Address='space.bilibili.com/2144306939';Url='https://space.bilibili.com/2144306939'},
    [pscustomobject]@{Name='X';Address='x.com/FlashDragon0429';Url='https://x.com/FlashDragon0429'}
  )
  for($i=0;$i -lt $links.Count;$i++){
    $linkTitle=[Windows.Forms.Label]::new()
    $linkTitle.Text=$links[$i].Name+'：'
    $linkTitle.Location=[Drawing.Point]::new(16,25+31*$i)
    $linkTitle.Size=[Drawing.Size]::new(122,25);$linkTitle.ForeColor=$mutedColor
    [void]$contacts.Controls.Add($linkTitle)
    $link=[Windows.Forms.LinkLabel]::new()
    $link.Text=$links[$i].Address;$link.Tag=$links[$i].Url
    $link.Location=[Drawing.Point]::new(145,25+31*$i)
    $link.Size=[Drawing.Size]::new(455,25)
    $link.LinkColor=$script:accent
    $link.ActiveLinkColor=Blend-Color $script:accent $textColor 0.3
    $link.VisitedLinkColor=$link.LinkColor
    $link.Add_LinkClicked({param($sender,$eventArgs) [void][Diagnostics.Process]::Start([string]$sender.Tag)})
    [void]$contacts.Controls.Add($link)
  }
  $notice=[Windows.Forms.Label]::new()
  $notice.Text='程序：MIT；TagLibSharp：LGPL-2.1-only（许可文件随附）。'
  $notice.Location=[Drawing.Point]::new(22,421);$notice.Size=[Drawing.Size]::new(615,22)
  $notice.ForeColor=$mutedColor
  [void]$about.Controls.Add($notice)
  $copy=[Windows.Forms.Button]::new()
  $copy.Text='复制信息';$copy.Location=[Drawing.Point]::new(20,454)
  $copy.Size=[Drawing.Size]::new(145,34)
  $copy.Add_Click({
    $clipboardText="LocalMusicPlayer 1.0.0.2`r`n世界重构 / FlashDragon / 庚辰`r`nhttps://github.com/FlashDragons/LocalMusicPlayer"
    [Windows.Forms.Clipboard]::SetText($clipboardText)
  })
  [void]$about.Controls.Add($copy)
  $ok=[Windows.Forms.Button]::new()
  $ok.Text='确定';$ok.Location=[Drawing.Point]::new(514,454)
  $ok.Size=[Drawing.Size]::new(126,34);$ok.DialogResult='OK'
  $about.AcceptButton=$ok;$about.CancelButton=$ok
  [void]$about.Controls.Add($ok)
  foreach($buttonControl in @($copy,$ok)){
    $buttonControl.FlatStyle='Flat';$buttonControl.UseVisualStyleBackColor=$false
    $buttonControl.BackColor=if($dark){[Drawing.Color]::FromArgb(53,56,62)}else{[Drawing.Color]::FromArgb(240,240,240)}
    $buttonControl.ForeColor=$textColor
    $buttonControl.FlatAppearance.BorderColor=if($dark){[Drawing.Color]::FromArgb(83,87,95)}else{[Drawing.Color]::FromArgb(180,184,190)}
  }
  $about.Add_Shown({[PlayerDwm]::SetDarkTitleBar($about.Handle,$dark)})
  try{[void]$about.ShowDialog($form)}
  finally{if($logo.Image){$logo.Image.Dispose()};$about.Dispose()}
}
$aboutMenu.Add_Click({Show-About})
foreach($modeItem in $modeMenuItems){
  $modeItem.Add_Click({
    param($sender,$eventArgs)
    $script:mode=[string]$sender.Tag
    foreach($option in $modeMenuItems){$option.Checked=($option.Tag -eq $script:mode)}
    $script:bag.Clear()
    Save-Config
  })
}
$play.Add_Click({
  if($script:current -lt 0){Play-Next}
  elseif($script:playing){
    $script:player.Pause();$script:playing=$false;$script:paused=$true
    Update-TransportIcons;Update-TaskbarProgress;$status.Text='已暂停'
  }else{
    $script:player.Play();$script:playing=$true;$script:paused=$false
    Update-TransportIcons;Update-TaskbarProgress
    $status.Text='正在播放  |  '+$script:tracks[$script:current].Name
  }
})
$next.Add_Click({Play-Next})
$prev.Add_Click({Play-Previous})
$stop.Add_Click({
  $script:player.Stop();$script:playing=$false;$script:paused=$false
  Update-TransportIcons;Update-TaskbarProgress
  $clock.Text='00:00 / 00:00';$seek.Value=0;$status.Text='已停止'
})
$form.Add_ThumbnailCommand({
  param($sender,$e)
  switch($e.CommandId){
    1 {$prev.PerformClick()}
    2 {$stop.PerformClick()}
    3 {$play.PerformClick()}
    4 {$next.PerformClick()}
  }
  $form.SetThumbnailState($script:playing,($script:tracks.Count -gt 0))
})
$list.Add_DoubleClick({
  if($list.SelectedIndices.Count -gt 0){Start-Track $list.SelectedIndices[0]}
})
$list.Add_KeyDown({
  param($sender,$e)
  if($e.KeyCode -eq [Windows.Forms.Keys]::Enter -and $list.SelectedIndices.Count -gt 0){
    $e.SuppressKeyPress=$true
    Start-Track $list.SelectedIndices[0]
  }
})
$volume.Add_ValueChanged({
  $script:vol=$volume.Value
  if($script:vol -gt 0){$script:lastAudibleVol=$script:vol}
  $script:muted=$false
  Apply-Volume
  $volPercent.Text="$script:vol%"
})
$muteButton.Add_Click({
  if($script:muted -or $script:vol -eq 0){
    if($script:vol -eq 0){$volume.Value=$script:lastAudibleVol}
    $script:muted=$false
  }else{$script:muted=$true}
  Apply-Volume
  Save-Config
})
$volume.Add_MouseEnter({[void]$volume.Focus()})
$volume.Add_MouseLeave({[void]$play.Focus()})
$volume.Add_MouseWheel({
  param($sender,$e)
  if($e.Delta -eq 0){return}
  $notches=[int][Math]::Truncate($e.Delta/[double][Windows.Forms.SystemInformation]::MouseWheelScrollDelta)
  if($notches -eq 0){$notches=[Math]::Sign($e.Delta)}
  $volume.Value=[Math]::Max(0,[Math]::Min(100,$volume.Value+5*$notches))
  if($e -is [Windows.Forms.HandledMouseEventArgs]){$e.Handled=$true}
  Save-Config
})
$list.Add_MouseEnter({[void]$list.Focus()})
$volume.Add_MouseUp({Save-Config})
$seek.Add_MouseDown({$script:seeking=$true})
$seek.Add_MouseUp({
  if($script:current -ge 0 -and $script:player.NaturalDuration.HasTimeSpan){
    $seconds=$script:player.NaturalDuration.TimeSpan.TotalSeconds
    $script:player.Position=[TimeSpan]::FromSeconds($seconds*$seek.Value/1000.0)
    Update-TaskbarProgress
  }
  $script:seeking=$false
})
$script:player.Add_MediaOpened({Apply-Volume;Update-TaskbarProgress})
$script:player.Add_MediaEnded({Play-Next $true})
$script:player.Add_MediaFailed({
  param($sender,$args)
  $script:playing=$false;$script:paused=$false;Update-TransportIcons;Update-TaskbarProgress
  $status.Text='播放失败：'+$args.ErrorException.Message
})
$timer=[Windows.Forms.Timer]::new();$timer.Interval=500
$script:themePoll=0
$timer.Add_Tick({
  $script:themePoll++
  if($script:themePoll -ge 4){$script:themePoll=0;Apply-Theme}
  $form.SetThumbnailState($script:playing,($script:tracks.Count -gt 0))
  Update-TaskbarProgress
  if($script:current -lt 0){return}
  $p=$script:player.Position
  if($script:player.NaturalDuration.HasTimeSpan){
    $d=$script:player.NaturalDuration.TimeSpan
    $clock.Text=('{0:mm\:ss} / {1:mm\:ss}' -f $p,$d)
    if(-not $script:seeking -and $d.TotalSeconds -gt 0){
      $seek.Value=[Math]::Max(0,[Math]::Min(1000,[int](1000*$p.TotalSeconds/$d.TotalSeconds)))
    }
  }else{$clock.Text=('{0:mm\:ss}' -f $p)}
})
function Set-PlaylistColumnWidth([bool]$reserveScrollbar) {
  if($form.IsDisposed -or $list.Columns.Count -lt 2){return}
  $reserve=if($reserveScrollbar){[Windows.Forms.SystemInformation]::VerticalScrollBarWidth+8}else{2}
  $width=[Math]::Max(160,$list.ClientSize.Width-$list.Columns[0].Width-$reserve)
  if($list.Columns[1].Width -ne $width){$list.Columns[1].Width=$width}
}
$form.Add_Shown({
  Set-PlaylistColumnWidth $true
  [void]$form.BeginInvoke([Action]{Set-PlaylistColumnWidth $false})
  [void]$play.Focus()
  Apply-Theme $true
})
$form.Add_Resize({
  Set-PlaylistColumnWidth $true
  if($form.IsHandleCreated){[void]$form.BeginInvoke([Action]{Set-PlaylistColumnWidth $false})}
})
$form.Add_FormClosing({
  $timer.Stop();Save-Config;$script:player.Close()
  foreach($transport in @($play,$stop,$prev,$next,$muteButton)){
    if($transport.Image){$transport.Image.Dispose();$transport.Image=$null}
  }
  $old=$cover.Image
  if($old -and -not [Object]::ReferenceEquals($old,$script:placeholderArt)){$old.Dispose()}
  if($script:placeholderArt){$script:placeholderArt.Dispose()}
})
Apply-Theme
if([IO.Directory]::Exists($script:path)){Record-RecentFolder $script:path}
Scan-Folder
$timer.Start()
[void]$form.ShowDialog()
$timer.Dispose();$script:player.Close();$form.Dispose()
