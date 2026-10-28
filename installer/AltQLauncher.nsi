# -*- coding: utf-8 -*-
Unicode true
RequestExecutionLevel user
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!ifndef APP_VERSION
  !error "必须由构建脚本提供 APP_VERSION"
!endif
!ifndef STAGE_DIR
  !error "必须由构建脚本提供 STAGE_DIR"
!endif
!ifndef OUT_FILE
  !error "必须由构建脚本提供 OUT_FILE"
!endif

Name "AltQLauncher ${APP_VERSION}"
OutFile "${OUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\AltQLauncher"
InstallDirRegKey HKCU "Software\AltQLauncher" "InstallDir"
SetCompressor /SOLID lzma
BrandingText "AltQLauncher"
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey /LANG=2052 "ProductName" "AltQLauncher"
VIAddVersionKey /LANG=2052 "FileDescription" "AltQLauncher 安装程序"
VIAddVersionKey /LANG=2052 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=2052 "LegalCopyright" "Copyright (c) 2026 AltQLauncher contributors"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\AltQLauncher.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "--settings"
!define MUI_FINISHPAGE_RUN_TEXT "运行 AltQLauncher 并打开设置"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${STAGE_DIR}\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"

Var TestMode
Var Parameters

Function .onInit
  SetShellVarContext current
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "本安装包需要 Windows 10/11 64 位系统。"
    Abort
  ${EndIf}
  StrCpy $TestMode 0
  ${GetParameters} $Parameters
  ClearErrors
  ${GetOptions} $Parameters "/TESTMODE" $0
  ${IfNot} ${Errors}
    ; 验证模式只解压到显式目录，不写注册表或创建快捷方式。
    StrCpy $TestMode 1
  ${EndIf}
FunctionEnd

Function .onVerifyInstDir
  ; 防止将文件直接散装到盘符根目录。
  ${GetRoot} "$INSTDIR" $0
  ${If} $INSTDIR == "$0\"
  ${OrIf} $INSTDIR == "$0"
    Abort
  ${EndIf}
FunctionEnd

Section "主程序（必选）" MainSection
  SectionIn RO
  SetOutPath "$INSTDIR"
  SetOverwrite on
  ; 明确文件清单，不覆盖 AltQLauncher.ini 或 AppData 用户配置。
  File "${STAGE_DIR}\AltQLauncher.exe"
  File "${STAGE_DIR}\AltQLauncher.default.ini"
  File "${STAGE_DIR}\README.md"
  File "${STAGE_DIR}\LICENSE"
  File "${STAGE_DIR}\THIRD-PARTY-NOTICES.md"
  SetOutPath "$INSTDIR\licenses"
  File "${STAGE_DIR}\licenses\AutoHotkey-GPL-2.0-and-PCRE.txt"
  SetOutPath "$INSTDIR\third-party-source"
  File "${STAGE_DIR}\third-party-source\AutoHotkey-v2.0.31-source.zip"
  SetOutPath "$INSTDIR\source"
  File "${STAGE_DIR}\source\AltQLauncher.ahk"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  ${If} $TestMode == 1
    FileOpen $0 "$INSTDIR\.test-install" w
    FileClose $0
  ${Else}
    WriteRegStr HKCU "Software\AltQLauncher" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "DisplayName" "AltQLauncher"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "Publisher" "AltQLauncher contributors"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "DisplayIcon" "$INSTDIR\AltQLauncher.exe"
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher" "NoRepair" 1
    CreateDirectory "$SMPROGRAMS\AltQLauncher"
    CreateShortcut "$SMPROGRAMS\AltQLauncher\AltQLauncher.lnk" "$INSTDIR\AltQLauncher.exe"
    CreateShortcut "$SMPROGRAMS\AltQLauncher\设置.lnk" "$INSTDIR\AltQLauncher.exe" "--settings"
    CreateShortcut "$SMPROGRAMS\AltQLauncher\卸载.lnk" "$INSTDIR\Uninstall.exe"
  ${EndIf}
SectionEnd

Section /o "桌面快捷方式" DesktopSection
  ${If} $TestMode != 1
    CreateShortcut "$DESKTOP\AltQLauncher.lnk" "$INSTDIR\AltQLauncher.exe"
  ${EndIf}
SectionEnd

Function un.onInit
  SetShellVarContext current
FunctionEnd

Section "Uninstall"
  ; 用户配置在 $APPDATA\AltQLauncher，始终保留。只删除本包的文件。
  IfFileExists "$INSTDIR\.test-install" skip_registration
    ReadRegStr $0 HKCU "Software\AltQLauncher" "InstallDir"
    ${If} $0 == $INSTDIR
      DeleteRegKey HKCU "Software\AltQLauncher"
      DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\AltQLauncher"
      Delete "$SMPROGRAMS\AltQLauncher\AltQLauncher.lnk"
      Delete "$SMPROGRAMS\AltQLauncher\设置.lnk"
      Delete "$SMPROGRAMS\AltQLauncher\卸载.lnk"
      RMDir "$SMPROGRAMS\AltQLauncher"
      Delete "$DESKTOP\AltQLauncher.lnk"
    ${EndIf}
  skip_registration:
  Delete "$INSTDIR\.test-install"
  Delete "$INSTDIR\AltQLauncher.exe"
  Delete "$INSTDIR\AltQLauncher.default.ini"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\THIRD-PARTY-NOTICES.md"
  Delete "$INSTDIR\licenses\AutoHotkey-GPL-2.0-and-PCRE.txt"
  RMDir "$INSTDIR\licenses"
  Delete "$INSTDIR\third-party-source\AutoHotkey-v2.0.31-source.zip"
  RMDir "$INSTDIR\third-party-source"
  Delete "$INSTDIR\source\AltQLauncher.ahk"
  RMDir "$INSTDIR\source"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
