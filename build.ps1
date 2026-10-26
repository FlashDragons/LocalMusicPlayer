# SPDX-License-Identifier: MIT
# Copyright (c) 2026 FlashDragon (世界重构 / 庚辰)
# Run with Windows PowerShell 5.1 on Windows with .NET Framework 4.6.2 or later.
if($PSVersionTable.PSEdition -ne 'Desktop'){
  throw '请使用 Windows PowerShell 5.1 运行 build.ps1。'
}
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $root 'build-icon.ps1')
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not [IO.File]::Exists($compiler)){
  $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if(-not [IO.File]::Exists($compiler)){throw '找不到 .NET Framework C# 编译器 csc.exe。'}
$automation=[System.Management.Automation.PowerShell].Assembly.Location
$source=Join-Path $root 'src\LocalMusicPlayer.Host.cs'
$icon=Join-Path $root 'assets\LocalMusicPlayer.ico'
$output=Join-Path $root 'LocalMusicPlayer.exe'
$arguments=@(
  '/nologo','/target:winexe','/platform:anycpu','/optimize+','/codepage:65001',
  "/out:$output","/win32icon:$icon",
  "/reference:$automation",'/reference:System.Windows.Forms.dll','/reference:System.Core.dll',
  $source
)
& $compiler @arguments
if($LASTEXITCODE -ne 0){throw '编译 LocalMusicPlayer.exe 失败。'}
Write-Host "已生成 $output"
