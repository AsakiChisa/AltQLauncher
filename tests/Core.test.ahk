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
