#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, StdOut
;@Ahk2Exe-SetName AltQLauncher
;@Ahk2Exe-SetDescription AltQLauncher 应用启动器
;@Ahk2Exe-SetVersion 1.0.1
;@Ahk2Exe-SetOrigFilename AltQLauncher.exe
;@Ahk2Exe-SetCopyright Copyright (c) 2026 AltQLauncher contributors

; AltQLauncher — 只在点击或 Enter 时启动。Alt 释放路径永远不调用 Run。
; 源码版/便携版配置在本地；安装版配置在当前用户 AppData，升级不覆盖。
if !(A_Args.Length && A_Args[1] = "--library") {
    try {
        RunLauncherApp()
    } catch as startupFailure {
        if HasLauncherArgument("--check")
            FileAppend(startupFailure.Message "`n" startupFailure.Stack "`n", "**", "UTF-8")
        else
            MsgBox("启动失败：`n" startupFailure.Message, "AltQLauncher", "Iconx")
        ExitApp(1)
    }
}

HasLauncherArgument(argument) {
    for value in A_Args {
        if value = argument
            return true
    }
    return false
}

LauncherDataDirectory(override := "") {
    if override != "" {
        if !RegExMatch(override, "i)^(?:[a-z]:\\|\\\\)")
            throw ValueError("--data-dir 必须使用绝对路径。")
        return RegExMatch(override, "i)^[a-z]:\\$") ? override : RTrim(override, "\")
    }
    if !A_IsCompiled || FileExist(A_ScriptDir "\portable.flag")
        return A_ScriptDir
    return A_AppData "\AltQLauncher"
}

RunLauncherApp() {
    dataOverride := ""
    index := 1
    while index <= A_Args.Length {
        argument := A_Args[index++]
        if argument = "--data-dir" {
            if index > A_Args.Length
                throw ValueError("--data-dir 后缺少目录。")
            dataOverride := A_Args[index++]
            if dataOverride = ""
                throw ValueError("--data-dir 目录不能为空。")
        } else if argument != "--settings" && argument != "--check" && argument != "--version" {
            throw ValueError("无法识别启动参数：" argument)
        }
    }
    if HasLauncherArgument("--version") {
        FileAppend("AltQLauncher 1.0.1`n", "*", "UTF-8")
        ExitApp(0)
    }
    directory := LauncherDataDirectory(dataOverride)
    DirCreate(directory)
    configPath := directory "\AltQLauncher.ini"
    if !FileExist(configPath) && FileExist(A_ScriptDir "\AltQLauncher.default.ini")
        FileCopy(A_ScriptDir "\AltQLauncher.default.ini", configPath)
    global Launcher := LauncherPanel(configPath)
    if HasLauncherArgument("--check") {
        ; 发布验证：构造真实控件但不显示窗口、不注册全局热键、不启动软件。
        Launcher.Scan([])
        Launcher.BuildGui()
        settings := LauncherSettings(Launcher)
        settings.Document()
        settings.Destroy()
        Launcher.Cleanup()
        FileAppend("PASS: AltQLauncher 1.0.1 config/ui preflight`n", "*", "UTF-8")
        ExitApp(0)
    }
    InstallKeybdHook()
    A_MenuMaskKey := "vkE8"
    Launcher.Start()
    if HasLauncherArgument("--settings")
        Launcher.OpenSettings()
}

class LauncherPanel {
    __New(configPath) {
        this.ConfigPath := configPath
        SplitPath(configPath,, &configDirectory)
        this.LogPath := configDirectory "\AltQLauncher.log"
        this.Visible := false
        this.Busy := false
        this.QDown := false
        this.SessionUsed := false
        this.PreviousWindow := 0
        this.CategoryIndex := 1
        this.Selected := 1
        this.HoverIndex := 0
        this.HoverSince := 0
        this.TooltipVisible := false
        this.PointerSignature := ""
        this.Items := []
        this.Categories := ["全部"]
        this.Groups := Map("全部", [])
        this.Icons := Map()
        this.Seen := Map()
        this.Warnings := 0
        this.LoadConfig()
        this.ReadConfig()
        this.WatchCallback := ObjBindMethod(this, "Watch")
    }

    ReadConfig() {
        this.TriggerKey := this.Read("Panel", "TriggerKey", "Q")
        if !RegExMatch(this.TriggerKey, "i)^(?:[a-z0-9]|F(?:[1-9]|1[0-9]|2[0-4]))$")
            throw ValueError("TriggerKey 只能是一个字母、数字或 F1–F24。")
        this.AltSide := StrLower(this.Read("Panel", "AltSide", "Either"))
        if !InStr("|either|left|right|", "|" this.AltSide "|")
            throw ValueError("AltSide 应为 Either、Left 或 Right。")
        this.Columns := this.Number("Panel", "Columns", 6, 3, 8)
        this.Rows := this.Number("Panel", "Rows", 3, 1, 5)
        this.PageSize := this.Columns * this.Rows
        this.Opacity := this.Number("Panel", "Opacity", 242, 120, 255)
        this.FontSize := this.Number("Panel", "FontSize", 10, 8, 14)
        this.ShowOther := this.Number("Panel", "ShowOther", 1, 0, 1)
        this.ShowAll := this.Number("Panel", "ShowAll", 1, 0, 1)
        this.CategoryOrder := []
        for row in StrSplit(this.Section("CategoryOrder"), "`n", "`r") {
            pair := this.Pair(row)
            if pair.Length && pair[2] != ""
                this.CategoryOrder.Push(pair[2])
        }
        this.UseMenuFolders := this.Number("Scan", "UseMenuFolders", 0, 0, 1)
        this.MaxItems := this.Number("Scan", "MaxItems", 3000, 20, 20000)
        this.MaxFiles := this.Number("Scan", "MaxFiles", 20000, 100, 200000)
        this.ExcludePattern := this.Read("Scan", "ExcludeRegex",
            "i)(uninstall|unins\d*|卸载|移除程序)")
        this.CheckRegex(this.ExcludePattern)
        this.Rules := []
        defaults := "开发=i)(visual studio|vscode|code -|pycharm|idea|git|python|docker|terminal)`n"
            . "办公=i)(word|excel|powerpoint|onenote|office|wps|notion|obsidian|acrobat)`n"
            . "网络=i)(chrome|firefox|edge|浏览器|微信|wechat|qq|telegram|thunderbird)`n"
            . "影音=i)(vlc|potplayer|music|音乐|视频|obs studio|photoshop|gimp|blender)`n"
            . "工具=i)(7-zip|winrar|everything|powertoys|计算器|记事本)"
        for row in StrSplit(this.Section("Rules", defaults), "`n", "`r") {
            pair := this.Pair(row)
            if !pair.Length
                continue
            this.CheckRegex(pair[2])
            if pair[1] = "全部"
                throw ValueError("Rules 中的分类名不能使用保留名称：全部。")
            this.Rules.Push({Name: pair[1], Pattern: pair[2]})
        }
    }

    LoadConfig() {
        ; Windows IniRead 的传统编码行为不适合 UTF-8 中文配置，明确用 UTF-8 读取。
        this.Config := Map()
        this.Config.CaseSense := "Off"
        if !FileExist(this.ConfigPath)
            return
        current := ""
        for line in StrSplit(FileRead(this.ConfigPath, "UTF-8"), "`n", "`r") {
            line := Trim(line)
            if line = "" || SubStr(line, 1, 1) = ";"
                continue
            if RegExMatch(line, "^\[([^\]]+)\]$", &match) {
                current := Trim(match[1])
                if current = "" || this.Config.Has(current)
                    throw ValueError("配置节为空或重复：" line)
                this.Config[current] := ""
            } else {
                if current = ""
                    throw ValueError("配置项必须放在 [节名] 下：" line)
                this.Pair(line)
                this.Config[current] .= line "`n"
            }
        }
    }

    Read(section, key, fallback) {
        for row in StrSplit(this.Section(section), "`n", "`r") {
            pair := this.Pair(row)
            if pair.Length && StrLower(pair[1]) = StrLower(key)
                return pair[2]
        }
        return fallback
    }

    Section(section, fallback := "") {
        return this.Config.Has(section) ? this.Config[section] : fallback
    }

    Number(section, key, fallback, low, high) {
        value := this.Read(section, key, fallback)
        if !IsInteger(value) || value < low || value > high
            throw ValueError(section "." key " 必须为 " low "–" high " 的整数。")
        return Integer(value)
    }

    Pair(row) {
        row := Trim(row)
        if row = "" || SubStr(row, 1, 1) = ";"
            return []
        pos := InStr(row, "=")
        if !pos
            throw ValueError("配置行缺少 = ：" row)
        return [Trim(SubStr(row, 1, pos - 1)), Trim(SubStr(row, pos + 1))]
    }

    CheckRegex(pattern) {
        if pattern != ""
            RegExMatch("", pattern)  ; 无效表达式在初始化时明确报错。
    }

    Start() {
        this.Scan()
        this.BuildGui()
        this.RegisterHotkeys()
        this.MakeTray()
        OnExit(ObjBindMethod(this, "Cleanup"))
        TrayTip("已收录 " this.Items.Length " 个条目。按 Alt+" this.TriggerKey " 打开。", "AltQLauncher")
    }

    Scan(menuRoots := unset) {
        ; 手动条目先收录，确保去重后仍保留用户设置的名称、分类和入口。
        for row in StrSplit(this.Section("Apps"), "`n", "`r") {
            pair := this.Pair(row)
            if !pair.Length
                continue
            fields := StrSplit(pair[2], "|", " `t")
            if fields.Length > 2 || fields[1] = ""
                throw ValueError("Apps 格式应为 主程序路径|分类。")
            path := this.ExpandPath(fields[1])
            if !FileExist(path) || InStr(FileExist(path), "D") {
                this.Log("跳过不存在的主程序：" path)
                continue
            }
            this.AddItem(path, fields.Length >= 2 ? fields[2] : "便携", pair[1])
        }
        ; 自动扫描只补充未收录的软件；快捷方式本身作为启动目标。
        if !IsSet(menuRoots)
            menuRoots := [A_Programs, A_ProgramsCommon]
        for root in menuRoots
            this.ScanRoot(root, "", true, false)
        for row in StrSplit(this.Section("PortableRoots"), "`n", "`r") {
            pair := this.Pair(row)
            if !pair.Length
                continue
            fields := StrSplit(pair[2], "|", " `t")
            if fields.Length > 3 || fields[1] = ""
                throw ValueError("PortableRoots 格式应为 路径|分类|递归(0/1)。")
            recursive := fields.Length >= 3 ? fields[3] : "0"
            if recursive != "0" && recursive != "1"
                throw ValueError("PortableRoots 递归开关只能是 0 或 1。")
            this.ScanRoot(this.ExpandPath(fields[1]), fields.Length >= 2 ? fields[2] : "便携",
                recursive = "1", true)
        }
        ; 固定排序使每次启动的选中位置可预测；不依赖文件系统枚举顺序。
        sorted := ""
        for index, item in this.Items
            sorted .= item.Name "`t" index "`n"
        ordered := []
        for row in StrSplit(Sort(RTrim(sorted, "`n")), "`n") {
            if row != ""
                ordered.Push(this.Items[Integer(SubStr(row, InStr(row, "`t",, -1) + 1))])
        }
        this.Items := ordered
        this.Groups := Map("全部", this.Items)
        for item in this.Items {
            if !this.Groups.Has(item.Category)
                this.Groups[item.Category] := []
            this.Groups[item.Category].Push(item)
        }
        this.Categories := []
        for rule in this.Rules {
            if this.Groups.Has(rule.Name) && !this.HasCategory(rule.Name)
                this.Categories.Push(rule.Name)
        }
        for name in this.Groups {
            if name != "全部" && !this.HasCategory(name)
                this.Categories.Push(name)
        }
        this.Categories.Push("全部")
        this.Categories := LauncherPanel.OrderCategories(this.Categories, this.CategoryOrder)
        this.Categories := this.VisibleCategoryNames(this.Categories)
        ; 图标只在扫描阶段读取；按键回调中不访问磁盘或 Shell。
        for item in this.Items
            item.Icon := this.LoadIcon(item.Path)
    }

    ; 显示顺序独立于规则匹配优先级；新增分类默认放在末尾“全部”之前。
    static OrderCategories(available, preferred) {
        names := Map()
        for name in available
            names[name] := true
        ordered := []
        seen := Map()
        for name in preferred {
            if names.Has(name) && !seen.Has(name) {
                ordered.Push(name)
                seen[name] := true
            }
        }
        allLast := ordered.Length && ordered[ordered.Length] = "全部"
        if allLast
            ordered.Pop()
        for name in available {
            if name != "全部" && !seen.Has(name) {
                ordered.Push(name)
                seen[name] := true
            }
        }
        if allLast || (names.Has("全部") && !seen.Has("全部"))
            ordered.Push("全部")
        return ordered
    }

    VisibleCategoryNames(ordered) {
        visible := []
        for name in ordered {
            if (name = "其他" && !this.ShowOther) || (name = "全部" && !this.ShowAll)
                continue
            visible.Push(name)
        }
        return visible
    }

    HasCategory(name) {
        for existing in this.Categories {
            if existing = name
                return true
        }
        return false
    }

    ScanRoot(root, forcedCategory, recursive, portable) {
        if !DirExist(root) {
            this.Log("扫描目录不存在：" root)
            return
        }
        pending := [root]
        cursor := 1
        visited := 0
        while cursor <= pending.Length {
            dir := pending[cursor++]
            try {
                Loop Files, dir "\*", "FD" {
                    visited += 1
                    if visited > this.MaxFiles || this.Items.Length >= this.MaxItems {
                        this.Log("达到扫描上限，已停止此目录：" root)
                        return
                    }
                    if InStr(A_LoopFileAttrib, "D") {
                        ; 不跟随 junction / symlink，避免递归环路及越出指定目录。
                        if recursive && !InStr(A_LoopFileAttrib, "L")
                            pending.Push(A_LoopFileFullPath)
                        continue
                    }
                    ext := StrLower(A_LoopFileExt)
                    if ext != "lnk" && ext != "url" && !(portable && ext = "exe")
                        continue
                    category := forcedCategory
                    if category = "" && this.UseMenuFolders {
                        relative := SubStr(A_LoopFileFullPath, StrLen(RTrim(root, "\")) + 2)
                        slash := InStr(relative, "\")
                        if slash
                            category := SubStr(relative, 1, slash - 1)
                    }
                    this.AddItem(A_LoopFileFullPath, category)
                }
            } catch as err {
                this.Log("目录扫描失败：" dir "；" err.Message)
            }
        }
    }

    AddItem(path, category := "", displayName := "") {
        if this.Items.Length >= this.MaxItems
            return
        SplitPath(path, &fileName, &dir, &ext, &base)
        name := displayName != "" ? displayName : base
        if this.ExcludePattern != "" && RegExMatch(name, this.ExcludePattern)
            return
        key := StrLower(path)
        if StrLower(ext) = "lnk" {
            try {
                FileGetShortcut(path, &target, &working, &args)
                ; 工作目录也属于快捷方式语义，不把不同工作目录的入口误合并。
                if target != ""
                    key := StrLower(target) "|" args "|" StrLower(working)
            } catch as err {
                ; 特殊 Shell / 广告快捷方式仍保留，启动时交由 Windows 处理。
                this.Log("快捷方式元数据不可读，保留原入口：" path "；" err.Message)
            }
        }
        if this.Seen.Has(key)
            return
        this.Seen[key] := true
        if category = "" {
            for rule in this.Rules {
                if rule.Pattern != "" && RegExMatch(name, rule.Pattern) {
                    category := rule.Name
                    break
                }
            }
        }
        if category = "" || category = "全部"
            category := "其他"
        this.Items.Push({Name: name, Path: path, WorkDir: dir, Category: category, Icon: 0})
    }

    ExpandPath(path) {
        path := StrReplace(path, "%A_ScriptDir%", A_ScriptDir)
        needed := DllCall("ExpandEnvironmentStringsW", "str", path, "ptr", 0, "uint", 0, "uint")
        if !needed
            throw OSError()
        output := Buffer(needed * 2)
        if !DllCall("ExpandEnvironmentStringsW", "str", path, "ptr", output, "uint", needed, "uint")
            throw OSError()
        result := StrGet(output)
        if !RegExMatch(result, "i)^(?:[a-z]:\\|\\\\)")
            result := A_ScriptDir "\" result
        return result
    }

    LoadIcon(path) {
        if this.Icons.Has(path)
            return this.Icons[path]
        info := Buffer(A_PtrSize + 688, 0)
        handle := 0
        if DllCall("shell32\SHGetFileInfoW", "str", path, "uint", 0, "ptr", info,
            "uint", info.Size, "uint", 0x100, "ptr")
            handle := NumGet(info, 0, "ptr")
        if !handle {
            try handle := LoadPicture(A_WinDir "\System32\shell32.dll", "Icon3 w32 h32", &kind)
            catch as err
                this.Log("备用图标不可用：" err.Message)
        }
        this.Icons[path] := handle
        return handle
    }

    BuildGui() {
        this.CellW := 116
        this.CellH := 102
        this.Width := 40 + this.Columns * this.CellW
        this.Height := 174 + this.Rows * this.CellH
        g := Gui("+AlwaysOnTop -Caption +ToolWindow", "AltQLauncher")
        this.Window := g
        g.BackColor := "171D2B"
        g.MarginX := 0
        g.MarginY := 0
        g.SetFont("s" this.FontSize " cE6EBF4", "Microsoft YaHei UI")
        g.AddText("x22 y15 w" (this.Width - 44) " h28 c96B9FF", "应用启动器    ALT + " StrUpper(this.TriggerKey))
        this.Heading := g.AddText("x22 y49 w" (this.Width - 110) " h28 +0x100", "")
        this.Heading.OnEvent("Click", (*) => this.Cycle(1))
        prev := g.AddText("x" (this.Width - 82) " y49 w28 h26 Center +0x100", "‹")
        next := g.AddText("x" (this.Width - 48) " y49 w28 h26 Center +0x100", "›")
        prev.OnEvent("Click", (*) => this.Cycle(-1))
        next.OnEvent("Click", (*) => this.Cycle(1))
        this.Tiles := []
        this.TileByHwnd := Map()
        Loop this.PageSize {
            slot := A_Index
            x := 20 + Mod(slot - 1, this.Columns) * this.CellW
            y := 86 + Floor((slot - 1) / this.Columns) * this.CellH
            frame := g.AddText("x" x " y" y " w108 h94 Background232C3D +0x100", "")
            bg := g.AddText("x" (x + 2) " y" (y + 2) " w104 h90 Background232C3D +0x100", "")
            pic := g.AddPicture("x" (x + 38) " y" (y + 10) " w32 h32 Background232C3D", "")
            label := g.AddText("x" (x + 4) " y" (y + 50) " w100 h40 Center +0x100 +0x80 Background232C3D", "")
            for ctrl in [frame, bg, pic, label] {
                ctrl.OnEvent("Click", ObjBindMethod(this, "ClickTile", slot))
                this.TileByHwnd[ctrl.Hwnd] := slot
            }
            this.Tiles.Push({Frame: frame, Bg: bg, Pic: pic, Label: label})
        }
        bottom := 92 + this.Rows * this.CellH
        this.Status := g.AddText("x22 y" bottom " w" (this.Width - 44) " h22 c96B9FF +0x80", "")
        g.AddText("x22 y" (bottom + 25) " w" (this.Width - 44) " h44 cA8B1C3",
            "Alt 保持 · " StrUpper(this.TriggerKey) " 分类 · 方向键选择 · 滚轮翻页`nEnter / 点击启动 · 松 Alt / Esc 隐藏")
        g.OnEvent("Close", (*) => this.Hide())
        g.OnEvent("Escape", (*) => this.Hide())
        g.Show("Hide w" this.Width " h" this.Height)
        WinSetTransparent(this.Opacity, g)
        this.Render()
    }

    RegisterHotkeys() {
        side := this.AltSide = "left" ? "<!" : this.AltSide = "right" ? ">!" : "!"
        ; $ 强制键盘钩子；不使用通配符，Ctrl+Alt/AltGr/Win 组合保持原行为。
        Hotkey("$" side this.TriggerKey, ObjBindMethod(this, "Trigger", 1), "On T1 B0")
        Hotkey("$+" side this.TriggerKey, ObjBindMethod(this, "Trigger", -1), "On T1 B0")
        ; Q 的重复 keydown 不重复切分类；任意修饰键状态下的 keyup 都能复位。
        Hotkey("~*" this.TriggerKey " Up", (*) => this.QDown := false)
        Hotkey("~*LAlt Up", ObjBindMethod(this, "AltReleased"))
        Hotkey("~*RAlt Up", ObjBindMethod(this, "AltReleased"))
        HotIf((*) => this.Visible && WinActive("ahk_id " this.Window.Hwnd))
        for key, delta in Map("Left", -1, "Right", 1, "Up", -this.Columns, "Down", this.Columns)
            Hotkey("*" key, ObjBindMethod(this, "Move", delta))
        Hotkey("*PgUp", ObjBindMethod(this, "Move", -this.PageSize))
        Hotkey("*PgDn", ObjBindMethod(this, "Move", this.PageSize))
        Hotkey("*Enter", ObjBindMethod(this, "ActivateSelected"))
        Hotkey("*NumpadEnter", ObjBindMethod(this, "ActivateSelected"))
        Hotkey("*Escape", (*) => this.Hide())
        HotIf(ObjBindMethod(this, "CanWheel"))
        ; * 使按住 Alt 时的滚轮也能触发；只拦截面板内的滚动。
        Hotkey("*WheelUp", ObjBindMethod(this, "Move", -this.PageSize))
        Hotkey("*WheelDown", ObjBindMethod(this, "Move", this.PageSize))
        HotIf()
    }

    CanWheel(*) {
        if !this.Visible || !this.Held() || !WinActive("ahk_id " this.Window.Hwnd)
            return false
        MouseGetPos(,, &hoverWindow)
        return hoverWindow = this.Window.Hwnd
    }

    Held() {
        if this.AltSide = "left"
            return GetKeyState("LAlt", "P")
        if this.AltSide = "right"
            return GetKeyState("RAlt", "P")
        return GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P")
    }

    Trigger(direction, *) {
        if this.QDown || !this.Held() || this.Busy
            return
        this.QDown := true
        if this.SessionUsed
            return
        if this.Visible
            this.Cycle(direction)
        else
            this.Show()
    }

    Show() {
        if !this.Held() || this.Busy
            return
        ; 仅将缓存界面的呈现作为短临界区；扫描和图标读取不在此执行。
        Critical("On")
        this.PreviousWindow := WinExist("A")
        this.Visible := true
        this.Render()
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        monitor := MonitorGetPrimary()
        Loop MonitorGetCount() {
            MonitorGet(A_Index, &ml, &mt, &mr, &mb)
            if mx >= ml && mx < mr && my >= mt && my < mb {
                monitor := A_Index
                break
            }
        }
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        scale := A_ScreenDPI / 96
        x := Max(left, Round((left + right - this.Width * scale) / 2))
        y := Max(top, Round((top + bottom - this.Height * scale) / 2))
        this.Window.Show("x" x " y" y " w" this.Width " h" this.Height)
        ; 记录初始位置，静止鼠标不会覆盖键盘选中项。
        MouseGetPos(&mx, &my, &pointerWindow, &pointerControl, 2)
        this.PointerSignature := mx "|" my "|" pointerWindow "|" pointerControl
        SetTimer(this.WatchCallback, 15)
        Critical("Off")
        ; GUI 显示期间也可能释放 Alt；最后再检查，杜绝“松开后才弹出”。
        if !this.Held()
            this.Hide()
    }

    AltReleased(*) {
        ; 释放任一 Alt 后，若另一个合格 Alt 仍按住则继续显示。
        if !this.Held() {
            this.SessionUsed := false
            this.Hide()
        }
    }

    Watch(*) {
        if !this.Held() {
            this.SessionUsed := false
            this.Hide()
        } else if this.Visible && !WinActive("ahk_id " this.Window.Hwnd) {
            ; 焦点丢失时取消，不抢夺其它应用焦点。
            this.Hide(false)
        } else if this.Visible {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mx, &my, &pointerWindow, &pointerControl, 2)
            this.HandlePointer(mx, my, pointerWindow, pointerControl)
        }
    }

    HandlePointer(x, y, pointerWindow, pointerControl) {
        if !this.Visible || !this.Held()
            return
        signature := x "|" y "|" pointerWindow "|" pointerControl
        moved := signature != this.PointerSignature
        this.PointerSignature := signature
        if pointerWindow != this.Window.Hwnd || !this.TileByHwnd.Has(pointerControl) {
            if this.HoverIndex {
                this.ClearHover()
                this.PaintTiles()
            }
            return
        }
        if moved {
            index := Floor((this.Selected - 1) / this.PageSize) * this.PageSize + this.TileByHwnd[pointerControl]
            if index > this.CurrentItems().Length {
                this.ClearHover()
                this.PaintTiles()
                return
            }
            if index != this.HoverIndex || index != this.Selected {
                this.ClearHover()
                this.HoverIndex := index
                this.HoverSince := A_TickCount
                this.Selected := index
                this.PaintTiles()
                this.RenderStatus()
            }
        }
        if this.HoverIndex && !this.TooltipVisible && A_TickCount - this.HoverSince >= 350 {
            item := this.CurrentItems()[this.HoverIndex]
            this.ShowItemTooltip(item)
            this.TooltipVisible := true
        }
    }

    ShowItemTooltip(item) {
        ToolTip(item.Name "`n" item.Path)
    }

    ClearHover() {
        this.HoverIndex := 0
        this.HoverSince := 0
        this.TooltipVisible := false
        ToolTip()
    }

    Hide(restore := true) {
        if !this.Visible
            return
        active := WinActive("ahk_id " this.Window.Hwnd)
        this.Visible := false  ; 先关启动门，再隐藏控件，排队的点击不能误执行。
        this.ClearHover()
        SetTimer(this.WatchCallback, 0)
        this.Window.Hide()
        if restore && active && this.PreviousWindow && WinExist("ahk_id " this.PreviousWindow) {
            try WinActivate("ahk_id " this.PreviousWindow)
            catch as err
                this.Log("恢复原窗口失败：" err.Message)
        }
    }

    CurrentItems() {
        return this.Categories.Length ? this.Groups[this.Categories[this.CategoryIndex]] : []
    }

    Cycle(direction, *) {
        if !this.Visible || !this.Held() || !this.Categories.Length
            return
        this.CategoryIndex := Mod(this.CategoryIndex - 1 + direction + this.Categories.Length,
            this.Categories.Length) + 1
        this.Selected := 1
        this.Render()
    }

    Move(delta, *) {
        if !this.Visible || !this.Held()
            return
        count := this.CurrentItems().Length
        if count {
            this.Selected := Min(count, Max(1, this.Selected + delta))
            this.Render()
        }
    }

    Render() {
        this.ClearHover()
        items := this.CurrentItems()
        count := items.Length
        page := Floor((this.Selected - 1) / this.PageSize)
        this.Heading.Text := this.Categories.Length ? this.CategoryIndex "/" this.Categories.Length "    "
            . this.Categories[this.CategoryIndex] "    ·    " count " 个" : "没有可显示的分类"
        for slot, tile in this.Tiles {
            index := page * this.PageSize + slot
            exists := index <= count
            tile.Frame.Visible := exists
            tile.Bg.Visible := exists
            tile.Pic.Visible := exists && items[index].Icon != 0
            tile.Label.Visible := exists
            if !exists
                continue
            item := items[index]
            tile.Label.Text := item.Name
            if item.Icon
                tile.Pic.Value := "HICON:*" item.Icon  ; 控件复制，缓存负责销毁原图标。
        }
        this.PaintTiles()
        this.RenderStatus()
    }

    TileColors(index) {
        if index = this.HoverIndex
            return {Fill: "48658F", Border: "A4C8FF"}
        if index = this.Selected
            return {Fill: "3B5279", Border: "638FCF"}
        return {Fill: "232C3D", Border: "232C3D"}
    }

    PaintTiles() {
        page := Floor((this.Selected - 1) / this.PageSize)
        count := this.CurrentItems().Length
        for slot, tile in this.Tiles {
            index := page * this.PageSize + slot
            if index > count
                continue
            colors := this.TileColors(index)
            tile.Frame.Opt("Background" colors.Border)
            for ctrl in [tile.Bg, tile.Pic, tile.Label]
                ctrl.Opt("Background" colors.Fill)
            for ctrl in [tile.Frame, tile.Bg, tile.Pic, tile.Label]
                ctrl.Redraw()
        }
    }

    RenderStatus() {
        items := this.CurrentItems()
        count := items.Length
        page := Floor((this.Selected - 1) / this.PageSize)
        this.Status.Text := count ? "第 " (page + 1) "/" Ceil(count / this.PageSize) " 页    ·    " items[this.Selected].Name
            : "没有条目；请检查开始菜单或配置 PortableRoots / Apps，然后在托盘菜单重新扫描。"
        if !this.Categories.Length
            this.Status.Text := "请在“设置 → 分类顺序”启用分类，或添加其他分类的软件。"
    }

    ClickTile(slot, *) {
        if !this.Visible || !this.Held()
            return
        index := Floor((this.Selected - 1) / this.PageSize) * this.PageSize + slot
        if index <= this.CurrentItems().Length {
            this.Selected := index
            this.ActivateSelected()
        }
    }

    ActivateSelected(*) {
        ; 唯一启动入口：必须面板可见、仍按 Alt、焦点仍在面板且未启动过。
        if !this.Visible || !this.Held() || this.SessionUsed || !WinActive("ahk_id " this.Window.Hwnd)
            return
        items := this.CurrentItems()
        if !items.Length
            return
        item := items[this.Selected]
        this.SessionUsed := true
        this.Hide()
        try {
            this.Launch(item)
            this.NotifyLaunch(item)
        }
        catch as err {
            this.Log("启动失败：" item.Name "；" err.Message)
            TrayTip("无法启动「" item.Name "」：" err.Message, "AltQLauncher", "Iconx")
        }
        ; 防止长按 Enter 或尚未松开的 Q 再开面板；释放 Alt 后解锁会话。
        SetTimer(ObjBindMethod(this, "ResetSession"), -30)
    }

    ResetSession(*) {
        if this.Held()
            SetTimer(ObjBindMethod(this, "ResetSession"), -30)
        else
            this.SessionUsed := false
    }

    NotifyLaunch(item) {
        TrayTip("已请求打开「" item.Name "」。", "AltQLauncher")
    }

    Launch(item) {
        if !FileExist(item.Path)
            throw TargetError("入口已移动或删除，请重新扫描。")
        SplitPath(item.Path,,, &ext)
        if StrLower(ext) = "lnk" {
            ; Run 会填入默认工作目录，覆盖 .lnk 的“起始位置”。Shell 的空目录参数
            ; 将参数、起始位置、显示状态及特殊快捷方式解析完整交给 Windows。
            result := DllCall("shell32\ShellExecuteW", "ptr", 0, "str", "open", "str", item.Path,
                "ptr", 0, "ptr", 0, "int", 1, "ptr")
            if result <= 32
                throw Error("Windows 无法打开快捷方式，Shell 错误码：" result)
        } else {
            Run('"' item.Path '"', item.WorkDir)
        }
    }

    MakeTray() {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Alt+" this.TriggerKey " 打开，松 Alt 隐藏", (*) => 0)
        A_TrayMenu.Disable("Alt+" this.TriggerKey " 打开，松 Alt 隐藏")
        A_TrayMenu.Add()
        A_TrayMenu.Add("设置", (*) => this.OpenSettings())
        A_TrayMenu.Default := "设置"
        A_TrayMenu.Add("编辑配置文件（高级）", (*) => this.OpenConfig())
        A_TrayMenu.Add("重新扫描 / 应用配置", (*) => Reload())
        A_TrayMenu.Add("查看按键记录（排障）", (*) => KeyHistory())
        A_TrayMenu.Add("退出", (*) => ExitApp())
        A_IconTip := "AltQLauncher · Alt+" this.TriggerKey
    }

    OpenSettings() {
        this.Hide()
        try {
            if !this.HasOwnProp("Settings") || !WinExist("ahk_id " this.Settings.Window.Hwnd)
                this.Settings := LauncherSettings(this)
            this.Settings.Window.Show()
        } catch as err {
            MsgBox("无法打开设置：`n" err.Message, "AltQLauncher", "Iconx")
        }
    }

    OpenConfig() {
        try Run('notepad.exe "' this.ConfigPath '"')
        catch as err
            MsgBox("无法打开配置：" err.Message, "AltQLauncher")
    }

    Log(message) {
        this.Warnings += 1
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", this.LogPath, "UTF-8")
        catch as err
            OutputDebug("AltQLauncher 日志写入失败：" err.Message)
    }

    Cleanup(*) {
        SetTimer(this.WatchCallback, 0)
        this.ClearHover()
        if this.HasOwnProp("Settings")
            this.Settings.Destroy()
        if this.HasOwnProp("Window")
            this.Window.Destroy()
        for path, handle in this.Icons {
            if handle
                DllCall("DestroyIcon", "ptr", handle)
        }
        this.Icons.Clear()
    }
}

; 设置窗口与启动面板独立；编辑期间的数据保存在内存，保存后才写入 INI。
class LauncherSettings {
    __New(owner) {
        this.Owner := owner
        this.Path := owner.ConfigPath
        this.SourceExists := FileExist(this.Path) != ""
        this.SourceText := this.SourceExists ? FileRead(this.Path, "UTF-8") : ""
        this.Model := LauncherPanel(this.Path)
        this.Apps := []
        this.Roots := []
        this.Rules := []
        this.Dirty := false
        this.Controls := Map()
        for row in StrSplit(this.Model.Section("Apps"), "`n", "`r") {
            pair := this.Model.Pair(row)
            if pair.Length {
                parts := StrSplit(pair[2], "|", " `t")
                if parts.Length > 2
                    throw ValueError("Apps 中有无法识别的条目：" pair[1])
                this.Apps.Push([pair[1], parts[1], parts.Length > 1 ? parts[2] : "便携"])
            }
        }
        for row in StrSplit(this.Model.Section("PortableRoots"), "`n", "`r") {
            pair := this.Model.Pair(row)
            if pair.Length {
                parts := StrSplit(pair[2], "|", " `t")
                if parts.Length > 3
                    throw ValueError("PortableRoots 中有无法识别的条目：" pair[1])
                recursive := parts.Length > 2 ? parts[3] : "0"
                if recursive != "0" && recursive != "1"
                    throw ValueError("目录递归开关必须为 0 或 1：" pair[1])
                this.Roots.Push([parts[1], parts.Length > 1 ? parts[2] : "便携", recursive = "1"])
            }
        }
        for rule in this.Model.Rules
            this.Rules.Push([rule.Name, rule.Pattern])
        available := []
        known := Map()
        for collection in [this.Owner.Categories, this.Model.CategoryOrder, this.CategoryNames()] {
            for name in collection {
                if name != "全部" && !known.Has(name) {
                    available.Push(name)
                    known[name] := true
                }
            }
        }
        available.Push("全部")
        this.OrderNames := LauncherPanel.OrderCategories(available, this.Model.CategoryOrder)
        this.Build()
    }

    Build() {
        g := Gui(, "AltQLauncher 设置")
        this.Window := g
        g.SetFont("s10", "Microsoft YaHei UI")
        g.AddText("x18 y14 w750 h25", "设置启动面板    修改后点击“保存并应用”生效")
        tabs := g.AddTab3("x16 y48 w768 h470", ["软件", "扫描目录", "分类规则", "快捷键与外观", "分类顺序"])
        tabs.UseTab(1)
        g.AddText("x34 y87 w724 h25", "管理手动添加的软件；开始菜单条目仍会自动扫描。双击条目可编辑。")
        this.AppList := g.AddListView("x34 y118 w728 h274 -Multi NoSortHdr", ["名称", "分类", "程序或快捷方式路径"])
        this.AppList.ModifyCol(1, 150)
        this.AppList.ModifyCol(2, 95)
        this.AppList.ModifyCol(3, 455)
        this.ListButtons("apps", 406)
        g.AddText("x34 y451 w716 h46", "可以浏览选择程序或 .lnk 快捷方式。需要启动参数时，请先建立快捷方式。`n删除这里只会移除手动配置，不会删除软件文件或开始菜单入口。")
        this.AppList.OnEvent("DoubleClick", (ctrl, row) => row ? this.EditEntry("apps") : 0)

        tabs.UseTab(2)
        g.AddText("x34 y87 w724 h25", "扫描便携软件文件夹；默认只扫描当前层，按需勾选包含子文件夹。")
        this.RootList := g.AddListView("x34 y118 w728 h208 -Multi NoSortHdr", ["目录", "分类", "包含子文件夹"])
        this.RootList.ModifyCol(1, 470)
        this.RootList.ModifyCol(2, 105)
        this.RootList.ModifyCol(3, 125)
        this.ListButtons("roots", 338)
        this.RootList.OnEvent("DoubleClick", (ctrl, row) => row ? this.EditEntry("roots") : 0)
        folderMode := g.AddCheckbox("x34 y380 w700 h24", "开始菜单按一级文件夹分类（否则按“分类规则”匹配）")
        folderMode.Value := this.Model.UseMenuFolders
        this.BindControl("UseMenuFolders", folderMode)
        this.Input("ExcludeRegex", "过滤名称（正则）", this.Model.ExcludePattern, 34, 414, 585)
        this.Input("MaxItems", "最多收录条目", this.Model.MaxItems, 34, 452, 140)
        this.Input("MaxFiles", "每目录扫描上限", this.Model.MaxFiles, 414, 452, 180)

        tabs.UseTab(3)
        g.AddText("x34 y87 w724 h25", "按从上到下的顺序匹配名称；首条命中生效，手动指定的分类优先。")
        this.RuleList := g.AddListView("x34 y118 w728 h274 -Multi NoSortHdr", ["分类", "匹配规则"])
        this.RuleList.ModifyCol(1, 150)
        this.RuleList.ModifyCol(2, 550)
        this.ListButtons("rules", 406)
        up := g.AddButton("x368 y406 w90 h30", "上移")
        down := g.AddButton("x470 y406 w90 h30", "下移")
        up.OnEvent("Click", (*) => this.ReorderRule(-1))
        down.OnEvent("Click", (*) => this.ReorderRule(1))
        this.RuleList.OnEvent("DoubleClick", (ctrl, row) => row ? this.EditEntry("rules") : 0)
        g.AddText("x34 y451 w716 h46", "新建分类可以直接填写关键词，用 | 分隔；已有高级正则也可编辑。`n未匹配的条目进入“其他”；空分类不会出现在启动面板。")

        tabs.UseTab(4)
        this.Input("TriggerKey", "Alt + 触发键", this.Model.TriggerKey, 34, 100, 120)
        g.AddText("x320 y104 w410 h25", "一个字母、数字或 F1–F24，例如 Q")
        g.AddText("x34 y150 w140 h26", "使用哪个 Alt")
        alt := g.AddDropDownList("x180 y146 w200", ["左右均可", "仅左 Alt", "仅右 Alt"])
        alt.Choose(this.Model.AltSide = "left" ? 2 : this.Model.AltSide = "right" ? 3 : 1)
        this.BindControl("AltSide", alt)
        this.Input("Columns", "每页列数（3–8）", this.Model.Columns, 34, 196, 120)
        this.Input("Rows", "每页行数（1–5）", this.Model.Rows, 414, 196, 120)
        this.Input("Opacity", "透明度（120–255）", this.Model.Opacity, 34, 246, 120)
        this.Input("FontSize", "字号（8–14）", this.Model.FontSize, 414, 246, 120)
        g.AddText("x34 y307 w716 h70", "透明度越小越透明，255 为完全不透明。`n屏幕较小或系统缩放较大时，可以减少每页的行列数。`n按住 Alt 维持面板，松 Alt 只隐藏；只有点击或 Enter 才启动。")
        tabs.UseTab(5)
        g.AddText("x34 y87 w724 h25", "选择分类后上移或下移。“全部”也可以调整到任意位置。")
        this.OrderList := g.AddListView("x34 y118 w728 h274 -Multi NoSortHdr", ["分类显示顺序"])
        this.OrderList.ModifyCol(1, 690)
        orderUp := g.AddButton("x34 y406 w100 h30", "上移")
        orderDown := g.AddButton("x146 y406 w100 h30", "下移")
        orderUp.OnEvent("Click", (*) => this.ReorderCategory(-1))
        orderDown.OnEvent("Click", (*) => this.ReorderCategory(1))
        showOther := g.AddCheckbox("x34 y447 w240 h26", "显示“其他”分类")
        showOther.Value := this.Model.ShowOther
        this.BindControl("ShowOther", showOther)
        showAll := g.AddCheckbox("x300 y447 w240 h26", "显示“全部”分类")
        showAll.Value := this.Model.ShowAll
        this.BindControl("ShowAll", showAll)
        g.AddText("x34 y484 w716 h26", "仅隐藏分类入口；排序不改变匹配优先级。保存并应用后生效。")
        tabs.UseTab()

        this.Status := g.AddText("x20 y528 w755 h24", "尚未修改配置")
        save := g.AddButton("x432 y558 w100 h32", "仅保存")
        apply := g.AddButton("x544 y558 w130 h32", "保存并应用")
        close := g.AddButton("x686 y558 w95 h32", "关闭")
        save.OnEvent("Click", (*) => this.Save(false))
        apply.OnEvent("Click", (*) => this.Save(true))
        close.OnEvent("Click", (*) => this.Close())
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())
        this.Refresh("apps")
        this.Refresh("roots")
        this.Refresh("rules")
        this.RefreshOrder()
        g.Show("Hide w800 h608")
    }

    BindControl(key, control) {
        this.Controls[key] := control
        ; CheckBox 仅支持 Click；Edit 和 DropDownList 使用 Change。
        eventName := control.Type = "CheckBox" ? "Click" : "Change"
        control.OnEvent(eventName, (*) => this.MarkDirty())
    }

    Input(key, label, value, x, y, width) {
        this.Window.AddText("x" x " y" (y + 4) " w142 h26", label)
        control := this.Window.AddEdit("x" (x + 146) " y" y " w" width " h28", value)
        this.BindControl(key, control)
    }

    ListButtons(kind, y) {
        for index, caption in ["添加", "编辑", "移除"] {
            button := this.Window.AddButton("x" (34 + (index - 1) * 106) " y" y " w94 h30", caption)
            if index = 1
                button.OnEvent("Click", ObjBindMethod(this, "EditEntry", kind, true))
            else if index = 2
                button.OnEvent("Click", ObjBindMethod(this, "EditEntry", kind, false))
            else
                button.OnEvent("Click", ObjBindMethod(this, "RemoveEntry", kind))
        }
    }

    Entries(kind) => kind = "apps" ? this.Apps : kind = "roots" ? this.Roots : this.Rules
    List(kind) => kind = "apps" ? this.AppList : kind = "roots" ? this.RootList : this.RuleList

    Refresh(kind, selected := 0) {
        list := this.List(kind)
        list.Delete()
        for entry in this.Entries(kind) {
            if kind = "apps"
                list.Add("", entry[1], entry[3], entry[2])
            else if kind = "roots"
                list.Add("", entry[1], entry[2], entry[3] ? "是" : "否")
            else
                list.Add("", entry[1], entry[2])
        }
        if selected > 0 && selected <= list.GetCount()
            list.Modify(selected, "Select Focus Vis")
    }

    MarkDirty() {
        this.Dirty := true
        this.Status.Text := "有未保存的修改"
    }

    CategoryNames() {
        names := []
        seen := Map()
        seen.CaseSense := "Off"
        for name in ["便携", "其他"] {
            names.Push(name)
            seen[name] := true
        }
        for collection in [this.Rules, this.Apps, this.Roots] {
            for entry in collection {
                name := collection = this.Rules ? entry[1] : collection = this.Apps ? entry[3] : entry[2]
                if name != "" && !seen.Has(name) {
                    names.Push(name)
                    seen[name] := true
                }
            }
        }
        return names
    }

    EditEntry(kind, adding := false, *) {
        if this.HasOwnProp("Dialog") {
            this.Dialog.Show()
            return
        }
        index := adding ? 0 : this.List(kind).GetNext()
        if !adding && !index {
            this.Status.Text := "请先选中一个条目"
            return
        }
        entry := index ? this.Entries(kind)[index] : kind = "apps" ? ["", "", "便携"]
            : kind = "roots" ? ["", "便携", false] : ["", ""]
        dialog := Gui("+Owner" this.Window.Hwnd, adding ? "添加" : "编辑")
        this.Dialog := dialog
        this.Window.Opt("+Disabled")
        dialog.SetFont("s10", "Microsoft YaHei UI")
        fields := Map()
        if kind = "apps" || kind = "rules" {
            dialog.AddText("x18 y20 w90 h26", kind = "apps" ? "软件名称" : "分类名称")
            fields["name"] := dialog.AddEdit("x116 y16 w438 h28", entry[1])
        }
        if kind = "apps" || kind = "roots" {
            y := kind = "apps" ? 62 : 20
            dialog.AddText("x18 y" (y + 4) " w90 h26", kind = "apps" ? "程序路径" : "扫描目录")
            fields["path"] := dialog.AddEdit("x116 y" y " w340 h28", kind = "apps" ? entry[2] : entry[1])
            browse := dialog.AddButton("x466 y" y " w88 h28", "浏览…")
            browse.OnEvent("Click", ObjBindMethod(this, "BrowseEntry", kind, fields))
            dialog.AddText("x18 y" (y + 50) " w90 h26", "所属分类")
            fields["category"] := dialog.AddComboBox("x116 y" (y + 46) " w438", this.CategoryNames())
            fields["category"].Text := kind = "apps" ? entry[3] : entry[2]
            if kind = "roots" {
                fields["recursive"] := dialog.AddCheckbox("x116 y116 w430 h26", "包含子文件夹（会收录子目录中的辅助程序）")
                fields["recursive"].Value := entry[3]
            }
        } else {
            dialog.AddText("x18 y66 w90 h26", "规则类型")
            fields["mode"] := dialog.AddDropDownList("x116 y62 w438", ["名称包含关键词（用 | 分隔）", "高级：正则表达式"])
            fields["mode"].Choose(adding ? 1 : 2)
            dialog.AddText("x18 y112 w90 h26", "匹配内容")
            fields["pattern"] := dialog.AddEdit("x116 y108 w438 h60 Multi", entry[2])
        }
        note := kind = "rules" ? "例如：微信|QQ|Telegram。已有规则以正则方式显示，保持类型即可。"
            : "支持相对路径和环境变量。配置在主窗口保存后才会写入文件。"
        dialog.AddText("x18 y188 w540 h48", note)
        ok := dialog.AddButton("x332 y244 w106 h32 Default", "确定")
        cancel := dialog.AddButton("x450 y244 w106 h32", "取消")
        ok.OnEvent("Click", ObjBindMethod(this, "AcceptEntry", kind, index, fields))
        cancel.OnEvent("Click", (*) => this.CloseDialog())
        dialog.OnEvent("Close", (*) => this.CloseDialog())
        dialog.OnEvent("Escape", (*) => this.CloseDialog())
        dialog.Show("w576 h294")
    }

    BrowseEntry(kind, fields, *) {
        try {
            ; 33 保留 .lnk 本身，不能把它解析成失去参数的目标文件。
            selected := kind = "roots" ? FileSelect("D",, "选择便携软件目录")
                : FileSelect(33,, "选择程序或快捷方式", "程序和快捷方式 (*.exe; *.lnk; *.url)")
            if selected = ""
                return
            fields["path"].Value := selected
            if kind = "apps" && Trim(fields["name"].Value) = "" {
                SplitPath(selected,,,, &base)
                fields["name"].Value := base
            }
        } catch as err {
            MsgBox("无法选择路径：" err.Message, "AltQLauncher 设置", "Iconx Owner" this.Dialog.Hwnd)
        }
    }

    AcceptEntry(kind, index, fields, *) {
        try {
            if kind = "rules" {
                pattern := Trim(fields["pattern"].Value)
                if fields["mode"].Value = 1
                    pattern := this.KeywordPattern(pattern)
                entry := [Trim(fields["name"].Value), pattern]
            } else {
                path := Trim(Trim(fields["path"].Value), '"')
                category := Trim(fields["category"].Text)
                entry := kind = "apps" ? [Trim(fields["name"].Value), path, category]
                    : [path, category, fields["recursive"].Value != 0]
            }
            this.ValidateEntry(kind, entry, index)
            entries := this.Entries(kind)
            if index
                entries[index] := entry
            else {
                entries.Push(entry)
                index := entries.Length
            }
            this.Refresh(kind, index)
            this.RefreshOrder()
            this.MarkDirty()
            this.CloseDialog()
        } catch as err {
            MsgBox(err.Message, "请检查输入", "Icon! Owner" this.Dialog.Hwnd)
        }
    }

    static KeywordsToRegex(text) {
        escaped := []
        for word in StrSplit(text, "|") {
            word := Trim(word)
            if word != ""
                escaped.Push(RegExReplace(word, "([\\.*+?\[\](){}^$])", "\$1"))
        }
        if !escaped.Length
            throw ValueError("请填写至少一个关键词。")
        result := ""
        for word in escaped
            result .= (result = "" ? "" : "|") word
        return "i)(" result ")"
    }

    KeywordPattern(text) => LauncherSettings.KeywordsToRegex(text)

    ValidateEntry(kind, entry, ignoreIndex := 0) {
        for index, value in entry {
            if index = 3 && kind = "roots"
                continue
            if RegExMatch(value, "[\r\n]")
                throw ValueError("名称、路径和规则必须写在一行中。")
        }
        if entry[1] = "" || (kind != "roots" && (SubStr(entry[1], 1, 1) = ";" || InStr(entry[1], "=")))
            throw ValueError("名称或目录不能为空；软件名和分类名不能包含 = 或以分号开头。")
        if kind = "rules" {
            if entry[1] = "全部"
                throw ValueError("“全部”是保留分类，请使用其它名称。")
            if entry[2] = ""
                throw ValueError("匹配规则不能为空。")
            this.Model.CheckRegex(entry[2])
        } else {
            path := kind = "apps" ? entry[2] : entry[1]
            category := kind = "apps" ? entry[3] : entry[2]
            if path = "" || InStr(path, "|") || InStr(path, '"')
                throw ValueError("请填写路径，路径不能包含 | 或双引号。")
            if category = "" || category = "全部" || InStr(category, "|")
                throw ValueError("请填写分类；分类不能是“全部”或包含 |。")
            this.Model.ExpandPath(path)
        }
        if kind != "roots" {
            for index, existing in this.Entries(kind) {
                if index != ignoreIndex && StrLower(existing[1]) = StrLower(entry[1])
                    throw ValueError("名称已存在，请使用不同的名称。")
            }
        }
    }

    RemoveEntry(kind, *) {
        index := this.List(kind).GetNext()
        if !index {
            this.Status.Text := "请先选中一个条目"
            return
        }
        this.Entries(kind).RemoveAt(index)
        this.Refresh(kind, Min(index, this.Entries(kind).Length))
        this.MarkDirty()
    }

    ReorderRule(delta) {
        index := this.RuleList.GetNext()
        target := index + delta
        if !index || target < 1 || target > this.Rules.Length
            return
        entry := this.Rules.RemoveAt(index)
        this.Rules.InsertAt(target, entry)
        this.Refresh("rules", target)
        this.MarkDirty()
    }

    RefreshOrder(selected := 0) {
        ; 也纳入本次编辑中新添加的分类，避免必须先重新加载才能排序。
        available := this.OrderNames.Clone()
        for name in this.CategoryNames()
            available.Push(name)
        this.OrderNames := LauncherPanel.OrderCategories(available, this.OrderNames)
        this.OrderList.Delete()
        for name in this.OrderNames
            this.OrderList.Add("", name)
        if selected > 0 && selected <= this.OrderNames.Length
            this.OrderList.Modify(selected, "Select Focus Vis")
    }

    ReorderCategory(delta) {
        index := this.OrderList.GetNext()
        target := index + delta
        if !index || target < 1 || target > this.OrderNames.Length
            return
        name := this.OrderNames.RemoveAt(index)
        this.OrderNames.InsertAt(target, name)
        this.RefreshOrder(target)
        this.MarkDirty()
    }

    CloseDialog() {
        this.Window.Opt("-Disabled")
        this.Dialog.Destroy()
        this.DeleteProp("Dialog")
        WinActivate(this.Window)
    }

    Document() {
        this.RefreshOrder()
        panel := Map()
        for key in ["TriggerKey", "Columns", "Rows", "Opacity", "FontSize"]
            panel[key] := Trim(this.Controls[key].Value)
        panel["AltSide"] := ["Either", "Left", "Right"][this.Controls["AltSide"].Value]
        panel["ShowOther"] := this.Controls["ShowOther"].Value
        panel["ShowAll"] := this.Controls["ShowAll"].Value
        scan := Map("UseMenuFolders", this.Controls["UseMenuFolders"].Value,
            "ExcludeRegex", Trim(this.Controls["ExcludeRegex"].Value),
            "MaxItems", Trim(this.Controls["MaxItems"].Value), "MaxFiles", Trim(this.Controls["MaxFiles"].Value))
        lists := Map("Apps", "", "PortableRoots", "", "Rules", "", "CategoryOrder", "")
        for index, name in this.OrderNames
            lists["CategoryOrder"] .= index "=" name "`n"
        for kind in ["apps", "roots", "rules"] {
            for index, entry in this.Entries(kind) {
                this.ValidateEntry(kind, entry, index)
                if kind = "apps"
                    lists["Apps"] .= entry[1] "=" entry[2] "|" entry[3] "`n"
                else if kind = "roots"
                    lists["PortableRoots"] .= index "=" entry[1] "|" entry[2] "|" (entry[3] ? 1 : 0) "`n"
                else
                    lists["Rules"] .= entry[1] "=" entry[2] "`n"
            }
        }
        return LauncherConfigFile.Merge(this.SourceText, Map("Panel", panel, "Scan", scan), lists)
    }

    Save(apply, *) {
        if this.HasOwnProp("Dialog")
            return false
        try {
            document := this.Document()
            LauncherConfigFile.Save(this.Path, document, this.SourceExists, this.SourceText)
            this.SourceText := document
            this.SourceExists := true
            this.Dirty := false
            this.Status.Text := "已保存。点击“保存并应用”可重新扫描并启用设置；原配置备份为 .ini.bak。"
            if apply
                Reload()
            return true
        } catch as err {
            MsgBox("未能保存或应用：`n" err.Message, "AltQLauncher 设置", "Iconx Owner" this.Window.Hwnd)
            return false
        }
    }

    Close() {
        if this.HasOwnProp("Dialog")
            return true
        if this.Dirty {
            answer := MsgBox("有未保存的修改，是否保存？`n选择“否”将放弃本次修改。", "AltQLauncher 设置",
                "YesNoCancel Icon? Owner" this.Window.Hwnd)
            if answer = "Cancel" || (answer = "Yes" && !this.Save(false))
                return true
        }
        this.Destroy()
        this.Owner.DeleteProp("Settings")
        return true
    }

    Destroy() {
        if this.HasOwnProp("Dialog")
            this.Dialog.Destroy()
        this.Window.Destroy()
    }
}

class LauncherConfigFile {
    ; 保留未知节/选项、注释和原换行；列表只替换有效条目，注释示例仍保留。
    static Merge(source, scalarSections, listSections) {
        eol := InStr(source, "`r`n") ? "`r`n" : "`n"
        scalars := Map()
        scalars.CaseSense := "Off"
        for section, values in scalarSections {
            normalized := Map()
            normalized.CaseSense := "Off"
            for key, value in values {
                if RegExMatch(value, "[\r\n]")
                    throw ValueError("配置值必须在一行内：" key)
                normalized[key] := value
            }
            scalars[section] := normalized
        }
        lists := Map()
        lists.CaseSense := "Off"
        for section, content in listSections
            lists[section] := content
        output := ""
        seen := Map()
        seen.CaseSense := "Off"
        current := ""
        written := Map()
        written.CaseSense := "Off"
        for line in StrSplit(RTrim(source, "`r`n"), "`n", "`r") {
            trimmed := Trim(line)
            if RegExMatch(trimmed, "^\[([^\]]+)\]$", &match) {
                output .= LauncherConfigFile.MissingKeys(current, scalars, written)
                current := Trim(match[1])
                seen[current] := true
                written := Map()
                written.CaseSense := "Off"
                output .= line "`n"
                if lists.Has(current)
                    output .= lists[current]
                continue
            }
            pos := InStr(trimmed, "=")
            active := trimmed != "" && SubStr(trimmed, 1, 1) != ";" && pos
            if active && lists.Has(current)
                continue
            if active && scalars.Has(current) {
                key := Trim(SubStr(trimmed, 1, pos - 1))
                if scalars[current].Has(key) {
                    if !written.Has(key)
                        output .= key "=" scalars[current][key] "`n"
                    written[key] := true
                    continue
                }
            }
            output .= line "`n"
        }
        output .= LauncherConfigFile.MissingKeys(current, scalars, written)
        for section, values in scalars {
            if !seen.Has(section)
                output .= "`n[" section "]`n" LauncherConfigFile.MissingKeys(section, scalars, Map())
        }
        for section, content in lists {
            if !seen.Has(section)
                output .= "`n[" section "]`n" content
        }
        return StrReplace(output, "`n", eol)
    }

    static MissingKeys(section, scalars, written) {
        result := ""
        if scalars.Has(section) {
            for key, value in scalars[section] {
                if !written.Has(key)
                    result .= key "=" value "`n"
            }
        }
        return result
    }

    static Save(path, document, expectedExists, expectedText) {
        LauncherConfigFile.CheckUnchanged(path, expectedExists, expectedText)
        temporary := path ".tmp." DllCall("GetCurrentProcessId") "." A_TickCount
        try {
            configStream := FileOpen(temporary, "w", "UTF-8-RAW")
            configStream.Write(document)
            configStream.Close()
            candidate := LauncherPanel(temporary)  ; 复用启动器的数值及正则校验。
            candidate.Cleanup()
            LauncherConfigFile.CheckUnchanged(path, expectedExists, expectedText)
            if expectedExists
                FileCopy(path, path ".bak", true)
            FileMove(temporary, path, true)
        } finally {
            if FileExist(temporary)
                FileDelete(temporary)
        }
    }

    static CheckUnchanged(path, expectedExists, expectedText) {
        exists := FileExist(path) != ""
        if exists != expectedExists || (exists && !(FileRead(path, "UTF-8") == expectedText))
            throw Error("配置文件已被其它编辑器修改。请关闭并重新打开设置，再合并修改；本次未覆盖文件。")
    }
}
