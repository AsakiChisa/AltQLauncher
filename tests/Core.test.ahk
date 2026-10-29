#Requires AutoHotkey v2.0
#Include ..\src\AltQLauncher.ahk

class CoreTestPanel extends LauncherPanel {
    Held() => true
    LoadIcon(*) => 0
    Log(message) => OutputDebug(message)
    Launch(*) {
        throw Error("测试不得启动程序")
    }
}

class HoverTestPanel extends CoreTestPanel {
    Requests := 0
    ActivateSelected(*) {
        this.Requests += 1
        this.RequestedIndex := this.Selected
    }
    ShowItemTooltip(item) {
        this.TipName := item.Name
    }
}

class PaintAuditPanel extends HoverTestPanel {
    PaintedCards := []
    ApplyTileColors(tile, colors) {
        this.PaintedCards.Push(tile.Frame.Hwnd)
        super.ApplyTileColors(tile, colors)
    }
}

Check(condition, message) {
    if !condition
        throw Error("FAIL: " message)
    FileAppend("PASS: " message "`n", "*", "UTF-8")
}

JoinTestCategories(values) {
    result := ""
    for value in values
        result .= (result = "" ? "" : "|") value
    return result
}

RunCoreTests() {
    try {
        root := A_Args[2] "\" DllCall("GetCurrentProcessId") "-" A_TickCount
        DirCreate(root "\menu")
        configPath := root "\test.ini"
        link := root "\menu\自动入口.lnk"
        FileCreateShortcut(A_AhkPath, link, A_WinDir, "one")
        FileCreateShortcut(A_AhkPath, root "\menu\相同入口.lnk", A_WinDir, "one")
        FileCreateShortcut(A_AhkPath, root "\menu\不同参数.lnk", A_WinDir, "two")
        stream := FileOpen(configPath, "w", "UTF-8-RAW")
        stream.Write("; keep-comment`n[Panel]`nShowOther=1`nShowAll=1`n[Rules]`n自动=i).`n[Apps]`n手动名称=" link "|常用`n")
        stream.Close()
        app := CoreTestPanel(configPath)
        app.Scan([root "\menu"])
        Check(app.Items.Length = 2 && app.Groups["常用"][1].Name = "手动名称", "手动分类优先，快捷方式去重保留不同参数")
        Check(app.Categories[app.Categories.Length] = "全部", "默认全部最后")
        Check(JoinTestCategories(LauncherPanel.OrderCategories(["常用", "工具", "全部"], ["全部", "工具"])) = "全部|工具|常用", "全部位置可自定义")
        Check(JoinTestCategories(LauncherPanel.OrderCategories(["常用", "工具", "全部"], ["常用", "全部"])) = "常用|工具|全部", "新增分类在末尾全部之前")
        app.ShowAll := false
        app.ShowOther := false
        Check(JoinTestCategories(app.VisibleCategoryNames(["其他", "常用", "全部"])) = "常用", "分类显示开关")
        app.ShowAll := true
        app.ShowOther := true
        app.BuildGui()
        hover := HoverTestPanel(configPath)
        hover.Scan([root "\menu"])
        hover.CategoryIndex := hover.Categories.Length
        hover.BuildGui()
        target := hover.Tiles[2].Label.Hwnd
        hover.HandlePointer(10, 10, hover.Window.Hwnd, target)
        Check(hover.Selected = 1 && hover.HoverIndex = 0, "隐藏时鼠标不能改变选择")
        hover.Visible := true
        hover.HandlePointer(10, 10, hover.Window.Hwnd, target)
        Check(hover.Selected = 2 && hover.HoverIndex = 2 && InStr(hover.Status.Text, hover.CurrentItems()[2].Name),
            "悬停卡片高亮并同步名称，不启动程序")
        Check(hover.TileColors(2).Border != hover.TileColors(1).Border && hover.Requests = 0, "悬停边框明显且不产生启动请求")
        hover.HoverSince := A_TickCount - 400
        hover.HandlePointer(10, 10, hover.Window.Hwnd, target)
        Check(hover.TooltipVisible && hover.TipName = hover.CurrentItems()[2].Name, "停留后显示对应软件完整名称")
        hover.Move(-1)
        hover.HandlePointer(10, 10, hover.Window.Hwnd, target)
        Check(hover.Selected = 1 && !hover.TooltipVisible, "静止鼠标不会覆盖键盘选择，旧提示清除")
        hover.HandlePointer(11, 10, hover.Window.Hwnd, target)
        Check(hover.Selected = 2 && hover.HoverIndex = 2, "鼠标重新移动恢复悬停选择")
        hover.HandlePointer(20, 20, 0, 0)
        Check(hover.HoverIndex = 0 && !hover.TooltipVisible && hover.Selected = 2, "移出面板清除悬停，保留键盘选中项")
        hover.ClickTile(1)
        Check(hover.Requests = 1 && hover.RequestedIndex = 1, "显式点击启动点击的软件，不误用之前悬停项")
        hover.Hide(false)
        Check(!hover.Visible && !hover.TooltipVisible && hover.HoverIndex = 0, "隐藏面板清除全部悬停反馈")
        hover.Cleanup()

        paged := PaintAuditPanel(configPath)
        icon := LoadPicture(A_AhkPath, "Icon1 w32 h32", &iconType)
        Check(icon && iconType = 1, "重绘检查使用真实软件图标")
        Loop 40
            paged.Items.Push({Name: "软件" A_Index, Path: "", WorkDir: "", Category: "全部", Icon: icon})
        paged.Groups := Map("全部", paged.Items)
        paged.Categories := ["全部"]
        paged.BuildGui()
        paged.Visible := true
        Check((WinGetExStyle(paged.Window) & 0x02000000) &&
            (WinGetStyle(paged.Tiles[1].Bg) & 0x04000000), "启用双缓冲及图标区域裁剪")
        untouchedImage := SendMessage(0x0173, 1, 0, paged.Tiles[4].Pic)
        paged.PaintedCards := []
        paged.HandlePointer(10, 10, paged.Window.Hwnd, paged.Tiles[2].Bg.Hwnd)
        Check(paged.PaintedCards.Length = 2, "切换悬停只更新前后两个卡片，不重绘整页")
        paged.PaintedCards := []
        paged.PaintTiles()
        paged.HandlePointer(11, 10, paged.Window.Hwnd, paged.Tiles[2].Label.Hwnd)
        Check(paged.PaintedCards.Length = 0, "相同高亮及同一卡片内移动不重复重绘")
        paged.PaintedCards := []
        Loop 20 {
            slot := Mod(A_Index, 2) ? 3 : 2
            paged.HandlePointer(20 + A_Index, 10, paged.Window.Hwnd, paged.Tiles[slot].Bg.Hwnd)
        }
        Check(paged.PaintedCards.Length = 40 &&
            untouchedImage = SendMessage(0x0173, 1, 0, paged.Tiles[4].Pic),
            "连续跨卡片移动仍只更新目标卡片，其他图标保持不变")
        paged.Selected := 1
        paged.Move(paged.PageSize)
        paged.HandlePointer(30, 30, paged.Window.Hwnd, paged.Tiles[2].Bg.Hwnd)
        Check(paged.Selected = 20 && paged.HoverIndex = 20, "翻页后按当前页映射悬停软件")
        paged.Move(20)
        paged.HandlePointer(31, 30, paged.Window.Hwnd, paged.Tiles[18].Frame.Hwnd)
        Check(paged.Selected = 40 && paged.HoverIndex = 0, "末页空白格不能悬停选择或启动")
        paged.Hide(false)
        paged.Cleanup()
        DllCall("DestroyIcon", "ptr", icon)

        editor := LauncherSettings(app)
        Check(editor.Controls["ShowAll"].Type = "CheckBox" && editor.OrderList.GetCount() > 0, "真实设置控件及事件绑定可创建（未显示）")
        editor.Controls["ShowAll"].Value := 0
        editor.Controls["ShowOther"].Value := 0
        document := editor.Document()
        savedPath := root "\saved.ini"
        LauncherConfigFile.Save(savedPath, document, false, "")
        saved := CoreTestPanel(savedPath)
        saved.Scan([root "\menu"])
        Check(!saved.HasCategory("全部") && saved.Items.Length = app.Items.Length, "设置保存后生效且不删除软件")
        Check(saved.Section("Apps") = app.Section("Apps"), "保存保留手动软件")
        Check(InStr(document, "; keep-comment"), "保存保留注释")
        rejected := false
        try LauncherConfigFile.Save(savedPath, document "`n", true, "stale-config")
        catch Error
            rejected := true
        Check(rejected, "检测外部编辑冲突")
        rejected := false
        try LauncherConfigFile.Save(savedPath, StrReplace(document, "Columns=6", "Columns=99"), true, document)
        catch ValueError
            rejected := true
        Check(rejected && FileRead(savedPath, "UTF-8") == document, "无效数值不能覆盖配置")
        pattern := LauncherSettings.KeywordsToRegex("C++|app.exe|中文")
        Check(RegExMatch("中文工具", pattern) && !RegExMatch("appZexe", pattern), "普通关键词按字面匹配")
        app.Categories := []
        app.Render()
        app.Visible := true
        app.Cycle(1)
        app.Move(app.PageSize)
        app.ClickTile(1)
        Check(app.CurrentItems().Length = 0, "所有分类隐藏后的安全处理")
        app.Visible := false
        editor.Destroy()
        saved.Cleanup()
        app.Cleanup()
        Check(LauncherDataDirectory(root) = root, "显式隔离数据目录")
        Check(LauncherDataDirectory("C:\") = "C:\", "数据目录为盘符根目录时保留绝对路径")
        Check(FileExist(root "\saved.ini") && !FileExist(root "\AltQLauncher.log"), "验证不启动外部软件")
        FileAppend("ALL CORE TESTS PASSED`n", "*", "UTF-8")
        ExitApp(0)
    } catch as failure {
        FileAppend(failure.Message "`n" failure.Stack "`n", "**", "UTF-8")
        ExitApp(1)
    }
}
RunCoreTests()
