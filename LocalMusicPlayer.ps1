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
        FillColor = Color.FromArgb(48, 139, 220);
        ThumbColor = Color.FromArgb(48, 139, 220);
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

    public void Dispose()
    {
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
$settingsToRead=if([IO.File]::Exists($script:config)){$script:config}elseif([IO.File]::Exists($legacyConfig)){$legacyConfig}else{$null}
if($settingsToRead){
  try {$s=Get-Content -LiteralPath $settingsToRead -Raw|ConvertFrom-Json
    if($s.Path -and (Test-Path -LiteralPath $s.Path -PathType Container)){$script:path=$s.Path}
    if($null -ne $s.Volume){$script:vol=[Math]::Max(0,[Math]::Min(100,[int]$s.Volume))}
    if($null -ne $s.Muted){$script:muted=[bool]$s.Muted}
    if($s.Mode -and $script:modeIds -contains [string]$s.Mode){$script:mode=[string]$s.Mode}
  }catch{}
}
function Save-Config {
  try {[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:config))
    @{Path=$script:path;Volume=$script:vol;Muted=$script:muted;Mode=$script:mode}|ConvertTo-Json|Set-Content -LiteralPath $script:config -Encoding UTF8
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
$script:seeking=$false
$extensions=@('.mp3','.wav','.wma','.m4a','.aac','.flac','.ogg')
$form=[PlayerForm]::new()
$form.Text='LocalMusicPlayer'
$form.Size=[Drawing.Size]::new(930,560)
$form.MinimumSize=[Drawing.Size]::new(760,450)
$form.StartPosition='CenterScreen'
$form.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)
try {
  $iconFile=Join-Path ([AppDomain]::CurrentDomain.BaseDirectory) 'LocalMusicPlayer.exe'
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
  $e.DrawDefault=(-not $script:themeDark)
})
$list.Add_DrawSubItem({
  param($sender,$e)
  if(-not $script:themeDark){$e.DrawDefault=$true;return}
  $background=if($e.Item.Selected){[Drawing.Color]::FromArgb(0,112,204)}else{$list.BackColor}
  $foreground=if($e.Item.Selected){[Drawing.Color]::White}else{$list.ForeColor}
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

$script:themeDark=$null
function Get-AppDarkTheme {
  try {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize')
    if($null -eq $key){return $false}
    try { return ([int]$key.GetValue('AppsUseLightTheme',1) -eq 0) }
    finally { $key.Dispose() }
  } catch { return $false }
}
function Apply-Theme([bool]$force=$false) {
  $dark=Get-AppDarkTheme
  if(-not $force -and $null -ne $script:themeDark -and $script:themeDark -eq $dark){return}
  $script:themeDark=$dark
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
  foreach($item in @($fileMenu,$chooseMenu,$addressMenu,$rescanMenu,$exitMenu,$modeMenu,$aboutMenu)+$modeMenuItems){
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
    $slider.FillColor=[Drawing.Color]::FromArgb(48,139,220)
    $slider.ThumbColor=[Drawing.Color]::FromArgb(48,139,220)
    $slider.Invalidate()
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
  foreach($label in @($now,$composerLabel,$albumLabel,$yearLabel)){$toolTip.SetToolTip($label,$label.Text)}
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
  $toolTip.SetToolTip($composerLabel,$composerLabel.Text)
  $toolTip.SetToolTip($albumLabel,$info.Album)
  $toolTip.SetToolTip($yearLabel,$yearLabel.Text)
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
    $script:current=$index;$script:playing=$true;Update-TransportIcons
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
  }catch{$script:playing=$false;Update-TransportIcons;$status.Text='无法播放：'+$_.Exception.Message}
}

function Finish-Playback([bool]$listFinished=$false) {
  $script:player.Stop()
  $script:playing=$false
  Update-TransportIcons
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
function Scan-Folder {
  $script:player.Stop();$script:player.Close()
  $script:current=-1;$script:playing=$false
  $script:bag.Clear();$script:history.Clear();$script:historyPos=-1
  Update-TransportIcons;$clock.Text='00:00 / 00:00';$seek.Value=0
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
  if($selected){$script:path=$selected;Scan-Folder}
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
    if([IO.Directory]::Exists($candidate)){
      $script:path=[IO.Path]::GetFullPath($candidate)
      Scan-Folder
    }else{
      [void][Windows.Forms.MessageBox]::Show($form,"目录不存在：$candidate",'无法切换目录')
    }
  }
  $addressDialog.Dispose()
})
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
    @('版本','1.0.0.0'),
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
    $link.LinkColor=[Drawing.Color]::FromArgb(73,158,236)
    $link.ActiveLinkColor=[Drawing.Color]::FromArgb(117,191,255)
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
    $clipboardText="LocalMusicPlayer 1.0.0.0`r`n世界重构 / FlashDragon / 庚辰`r`nhttps://github.com/FlashDragons/LocalMusicPlayer"
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
    $script:player.Pause();$script:playing=$false;Update-TransportIcons;$status.Text='已暂停'
  }else{
    $script:player.Play();$script:playing=$true;Update-TransportIcons
    $status.Text='正在播放  |  '+$script:tracks[$script:current].Name
  }
})
$next.Add_Click({Play-Next})
$prev.Add_Click({
  if($script:historyPos -gt 0){
    $script:historyPos--;Start-Track $script:history[$script:historyPos] $false
  }elseif($script:current -ge 0){$script:player.Position=[TimeSpan]::Zero}
})
$stop.Add_Click({
  $script:player.Stop();$script:playing=$false;Update-TransportIcons
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
  }
  $script:seeking=$false
})
$script:player.Add_MediaOpened({Apply-Volume})
$script:player.Add_MediaEnded({Play-Next $true})
$script:player.Add_MediaFailed({
  param($sender,$args)
  $script:playing=$false;Update-TransportIcons
  $status.Text='播放失败：'+$args.ErrorException.Message
})
$timer=[Windows.Forms.Timer]::new();$timer.Interval=500
$script:themePoll=0
$timer.Add_Tick({
  $script:themePoll++
  if($script:themePoll -ge 4){$script:themePoll=0;Apply-Theme}
  $form.SetThumbnailState($script:playing,($script:tracks.Count -gt 0))
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
Scan-Folder
$timer.Start()
[void]$form.ShowDialog()
$timer.Dispose();$script:player.Close();$form.Dispose()
