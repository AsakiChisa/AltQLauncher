# 第三方组件和来源

本项目原创 `.ahk`、PowerShell、NSIS 和说明文件使用 MIT。第三方组件保留其原授权；项目 MIT 声明不改变第三方授权。

## AutoHotkey 2.0.31

- 项目：[AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.31)。
- 二进制来源：[官方 v2.0.31 发布](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.31)。
- 使用未修改的官方 64 位运行时，通过 Ahk2Exe 嵌入本项目脚本。
- 运行时使用 GNU GPL version 2，相关 PCRE 授权也在原授权文本中。授权副本为 `licenses/AutoHotkey-GPL-2.0-and-PCRE.txt`。
- 对应完整上游源码归档：仓库 `vendor/AutoHotkey-v2.0.31-source.zip`；安装和便携发行包中的 `third-party-source/AutoHotkey-v2.0.31-source.zip`。本项目源码随二进制放在 `source/AltQLauncher.ahk`，构建脚本随 Source ZIP 提供。
- 分发包含该运行时的组合二进制时，请保留 GPL 文本和对应源码，不要只声称整个 EXE 仅为 MIT。

## Ahk2Exe 1.1.37.02a2（仅构建使用）

- 来源：[AutoHotkey/Ahk2Exe 官方发布](https://github.com/AutoHotkey/Ahk2Exe/releases/tag/Ahk2Exe1.1.37.02a2)。
- 本工具仅下载到构建缓存，不随应用安装。
- 官方发布 SHA256 固定在 `scripts/tools.lock.json`。

## NSIS 3.13（仅构建使用）

- 来源：[NSIS 官方下载](https://nsis.sourceforge.io/Download)、[授权说明](https://nsis.sourceforge.io/License)。
- 使用 NSIS 生成安装和卸载程序；完整 NSIS 编译器不随应用安装。
- 构建器归档 SHA256 固定在 `scripts/tools.lock.json`。

官方依赖归档均通过 HTTPS 下载。每次构建在使用前验证固定 SHA256；本地缓存不符时会停止，不会自动忽略校验。
