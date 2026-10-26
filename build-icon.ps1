# SPDX-License-Identifier: MIT
# Copyright (c) 2026 FlashDragon (世界重构 / 庚辰)
# Build a true-color, multi-resolution Windows icon from the original PNG.
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$sourcePath=Join-Path $root 'assets\logo.png'
$targetPath=Join-Path $root 'assets\LocalMusicPlayer.ico'
$source=[Drawing.Bitmap]::new($sourcePath)
$images=[Collections.Generic.List[byte[]]]::new()
$sizes=@(16,32,48,64,128,256)
try {
  foreach($size in $sizes){
    $bitmap=[Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
      $graphics=[Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.Clear([Drawing.Color]::Transparent)
        $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
        $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,$size,$size))
      } finally {$graphics.Dispose()}
      $stream=[IO.MemoryStream]::new()
      try {$bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png);$images.Add($stream.ToArray())}
      finally {$stream.Dispose()}
    } finally {$bitmap.Dispose()}
  }
} finally {$source.Dispose()}
$file=[IO.File]::Create($targetPath)
$writer=[IO.BinaryWriter]::new($file)
try {
  $writer.Write([uint16]0)
  $writer.Write([uint16]1)
  $writer.Write([uint16]$images.Count)
  $offset=6+16*$images.Count
  for($i=0;$i -lt $images.Count;$i++){
    $entrySize=if($sizes[$i] -eq 256){0}else{$sizes[$i]}
    $writer.Write([byte]$entrySize)
    $writer.Write([byte]$entrySize)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length)
    $writer.Write([uint32]$offset)
    $offset+=$images[$i].Length
  }
  foreach($image in $images){$writer.Write($image)}
} finally {$writer.Dispose()}
Write-Host "已生成 $targetPath"
