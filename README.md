# LocalMusicPlayer

LocalMusicPlayer 是一个 Windows 本地音乐播放器，版本 **1.0.0.0**。支持播放列表、专辑封面和标签信息、五种播放模式、任务栏缩略图控制，以及跟随系统的深浅色主题。
由 ChatGPT 制作。

作者：**世界重构 / FlashDragon / 庚辰**（同一人）

- 项目仓库：<https://github.com/FlashDragons/LocalMusicPlayer>
- 个人网站：<https://flashdragons.github.io>
- 哔哩哔哩：<https://space.bilibili.com/2144306939>
- X：<https://x.com/FlashDragon0429>

## 使用

将 `LocalMusicPlayer.exe`、`LocalMusicPlayer.ps1` 和 `TagLibSharp.dll` 放在同一目录，双击 EXE 启动。完整操作见 `使用说明.txt`。

首次启动默认扫描 `%USERPROFILE%\Music`，在大多数电脑上即 `C:\Users\[用户名]\Music`。如果这个目录不存在，则改用 Windows 的“音乐”文件夹位置。程序会递归扫描音乐文件。配置文件位于 `%LOCALAPPDATA%\LocalMusicPlayer\settings.json`，保留上次选择的目录和播放设置。

运行环境为 Windows PowerShell 5.1、.NET Framework 4.6.2 或更高版本，以及 Windows 桌面媒体组件。支持扫描 MP3、WAV、WMA、M4A、AAC、FLAC、OGG；实际解码能力取决于 Windows 媒体组件。

## 源码与构建

播放器界面和逻辑位于 `LocalMusicPlayer.ps1`；无控制台启动器源码位于 `src/LocalMusicPlayer.Host.cs`。图标素材位于 `assets/`。

在 Windows PowerShell 5.1 中运行 `./build.ps1`，即可使用系统自带的 .NET Framework C# 编译器生成 `LocalMusicPlayer.exe`。构建不需要下载完整 .NET SDK。运行时仍需把 `TagLibSharp.dll` 放在 EXE 旁边。

## 许可

LocalMusicPlayer 自有源码按 [MIT 许可](LICENSE)发布。随程序分发的 `TagLibSharp.dll` 是独立组件，采用 LGPL-2.1-only；其许可正文见 [TagLibSharp-LICENSE.txt](TagLibSharp-LICENSE.txt)，源码见 [mono/taglib-sharp](https://github.com/mono/taglib-sharp)。两份许可证分别适用于各自的代码。
