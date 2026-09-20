#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName AION2_Chs Patch
;@Ahk2Exe-SetOrigFilename AION2_Chs_P.exe
;@Ahk2Exe-SetProductName AION2_Chs Patch
;@Ahk2Exe-SetDescription AION2 一键汉化工具
;@Ahk2Exe-SetVersion 1.0.0.0
;@Ahk2Exe-SetCopyright Copyright © 2026
;@Ahk2Exe-SetMainIcon D:\Program Files\AutoHotkey\icon.ico
#Include "D:\Program Files\AutoHotkey\lib\UniqueInstance.ahk"
;@format array_style: expand, object_style: expand

#NoTrayIcon
Persistent true
#SingleInstance Off

uiResult := UniqueInstance.Ensure(Map(
    "preferRunAsAdmin", true,
    "allowCoexist", true,
    "showReport", true,
))

SplitPath(A_ScriptName, , , , &fileName)
configFile := "config.ini"
installPath := ""
sectionName := ""

servers := [
    {
        id: 101,
        name: "国际服",
        displayDescription: "国际服 - Steam / PURPLE",
        keywords: [
            "AION 2 Playtest",
            "AION 2",
            "AION2",
            "Aion2",
            "Aion 2"
        ]
    },
    {
        id: 102,
        name: "台服",
        displayDescription: "台服 - PURPLE",
        keywords: [
            "AION 2 Playtest",
            "AION 2",
            "AION2",
            "Aion2",
            "Aion 2"
        ]
    }
]

dropDownOptions := []
for server in servers {
    dropDownOptions.Push(server.displayDescription)
}

configCache := {
    Settings: {
        LastServerID: 101
    }
}
for server in servers {
    loopSectionName := "Server_" . server.id
    configCache.%loopSectionName% := {
        installPath: "",
        isManualReset: 0
    }
}

global currentServer := servers

; ==================== GUI 布局开始 ====================
myGui := Gui(, "AION2 一键汉化工具 1.0 beta")
myGui.SetFont("s9", "Microsoft YaHei")
; myGui.BackColor := "White"

; 添加 Tab 选项卡
tabCtrl := myGui.AddTab3("x-1 y10 w574 h460", [
    "中文汉化",
    "免费加速器"
])

; --- Tab 1 ---
tabCtrl.UseTab(1)

myGui.AddGroupBox("x17 y45 w536 h75", " 选择服务器 * ")
serverComboBox := myGui.AddDropDownList("x27 y75 w516 Choose1", dropDownOptions)

myGui.AddGroupBox("x17 y130 w536 h115", " 选择安装目录 * ")
pathEdit := myGui.AddEdit("x27 y160 w516 r1 ReadOnly", "")
btnScan := myGui.AddButton("x345 y201 w65 h26", "查找")
btnBrowse := myGui.AddButton("x417 y201 w60 h26", "浏览...")
btnReset := myGui.AddButton("x484 y201 w60 h26 +Disabled", "重置")

myGui.AddGroupBox("x17 y255 w536 h145", "使用须知 * ")
noticeControl := myGui.AddText("x31 y280 w510 h105", "")

btnChinese := myGui.AddButton("x182 y418 w100 h32", "一键汉化")
btnRestore := myGui.AddButton("x289 y418 w100 h32", "撤销汉化")

; --- Tab 2 布局内容 ---
tabCtrl.UseTab(2)

; myGui.AddGroupBox("x17 y45 w536 h390", "免费加速器推荐")
myGui.AddLink("x31 y75 w510 r1",
    '<a href="https://www.ggkuai.com/">古怪加速器 - 每天0-16点免费，极速稳定全球网游加速。</a>'
)
myGui.AddLink("x31 y100 w510 r1",
    '<a href="https://www.akspeedy.com/html/invite_new/invite_download.html?inviter=3Xtkus4t">AK加速器- 每天0-14点免费，支持全球网游加速。</a>'
)
myGui.AddLink("x31 y125 w510 r1",
    '<a href="https://www.xiaoyao.co/index.htm">逍遥加速器 - 24小时免费加速，全新模式 - 平台加速。支持 Steam、EA、Epic、暴雪等平台。</a>'
)

; --- 退出 Tab 作用域，恢复全局组件 ---
tabCtrl.UseTab(0)

statusBar := myGui.AddStatusBar(, "")
; ==================== GUI 布局结束 ====================

serverComboBox.OnEvent("Change", (*) => SelectServer())
btnScan.OnEvent("Click", (*) => OnScanButtonClick())
btnBrowse.OnEvent("Click", BrowseFolder)
btnReset.OnEvent("Click", DoReset)
btnChinese.OnEvent("Click", DoChinese)
btnRestore.OnEvent("Click", DoRestore)
myGui.OnEvent("Close", (*) => ExitApp())

myGui.Show("w570 h490")

; 页面加载与配置初始化
ReadConfig()

ReadConfig() {
    global configFile, configCache, servers, currentServer, serverComboBox
    local lastID, server, loopSectionName, targetIndex, index

    lastID := Number(IniRead(configFile, "Settings", "LastServerID", servers[1].id))

    for server in servers {
        loopSectionName := "Server_" . server.id
        configCache.%loopSectionName%.installPath := IniRead(configFile, loopSectionName, "installPath", "")
        configCache.%loopSectionName%.isManualReset := Number(IniRead(configFile, loopSectionName, "isManualReset", 0))
    }

    targetIndex := 1
    for index, server in servers {
        if (server.id == lastID) {
            targetIndex := index
            break
        }
    }

    serverComboBox.Value := targetIndex
    currentServer := servers[targetIndex]

    configCache.Settings.LastServerID := currentServer.id
    RefreshServerData()

    if (installPath == "") {
        SilentDetectFolder()
    }
}

; 切换服务器事件
SelectServer() {
    global configCache, currentServer, servers, serverComboBox

    currentServer := servers[serverComboBox.Value]
    configCache.Settings.LastServerID := currentServer.id
    SaveAllConfig()

    RefreshServerData()
    ShowStatus("已切换至 " . currentServer.name . " 配置。")

    if (installPath == "") {
        SilentDetectFolder()
    }
}

; 核心刷新与效验逻辑
RefreshServerData() {
    global sectionName, installPath, pathEdit, configCache, currentServer
    local savedPath, promptText

    sectionName := "Server_" . currentServer.id
    UpdateNoticeText()

    savedPath := configCache.%sectionName%.installPath
    if (savedPath != "") {
        if (DirExist(savedPath) && FileExist(savedPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            installPath := savedPath
            pathEdit.Value := savedPath
        } else {
            installPath := ""
            pathEdit.Value := ""
            configCache.%sectionName%.installPath := ""
            SaveAllConfig()

            promptText := "未检测到有效的安装目录，安装目录参数已重置。"
            PopupPrompt(promptText)
        }
    } else {
        installPath := ""
        pathEdit.Value := ""
    }

    RefreshUI()
}

; 提取公共的注册表有效路径筛选逻辑
GetValidGamePaths() {
    global currentServer
    local detectedGames, validGames, gameInfo

    detectedGames := ScanRegistryForGamePaths(currentServer.keywords)
    validGames := []

    for gameInfo in detectedGames {
        if (FileExist(gameInfo.gameInstallPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            validGames.Push(gameInfo)
        }
    }
    return validGames
}

; 静默自动扫描函数
SilentDetectFolder() {
    global installPath, sectionName, pathEdit, configCache

    if (configCache.%sectionName%.isManualReset == 1) {
        return
    }

    local validGames := GetValidGamePaths()

    if (validGames.Length = 1) {
        local selectedFolder := validGames[1].gameInstallPath
        pathEdit.Value := selectedFolder
        installPath := selectedFolder

        configCache.%sectionName%.installPath := selectedFolder
        SaveAllConfig()
        RefreshUI()
        ShowStatus("已自动识别并设置安装目录。")
    }
}

; 扫描按钮检测函数
OnScanButtonClick() {
    global installPath, sectionName, pathEdit, configCache, currentServer, configFile
    local validGames, selectedFolder

    validGames := GetValidGamePaths()
    selectedFolder := ""

    if (validGames.Length = 1) {
        selectedFolder := validGames[1].gameInstallPath
        ShowStatus("AION2 " . currentServer.name . "安装目录设置成功。")
    } else if (validGames.Length > 1) {
        selectedFolder := ShowMultiPathDialog(validGames)
        if (selectedFolder = "") {
            return
        }
        ShowStatus("AION2 " . currentServer.name . "安装目录设置成功。")
    } else {
        PopupPrompt("未检测到有效的安装目录，请通过[浏览...]按钮手动指定。")
        return
    }

    pathEdit.Value := selectedFolder
    installPath := selectedFolder

    configCache.%sectionName%.installPath := selectedFolder

    SaveAllConfig()
    RefreshUI()
}

; 手动浏览安装目录
BrowseFolder(*) {
    global installPath, sectionName, pathEdit, configCache, currentServer
    local promptText, selectedFolder, errorText

    promptText := "选择 AION2 " . currentServer.name . "安装目录："
    selectedFolder := FileSelect("D", pathEdit.Value, promptText)
    if (selectedFolder = "") {
        return
    }

    if (!FileExist(selectedFolder . "\Aion2\Binaries\Win64\Aion2.exe")) {
        errorText := "所选目录中未检测主程序 Aion2.exe，请重新选择正确的安装目录。"
        PopupPrompt(errorText)
        return
    }

    pathEdit.Value := selectedFolder
    installPath := selectedFolder

    configCache.%sectionName%.installPath := selectedFolder

    SaveAllConfig()

    ShowStatus("AION2 " . currentServer.name . "安装目录设置成功。")
    RefreshUI()
}

; 用户选择安装目录
ShowMultiPathDialog(validGames) {
    global myGui, currentServer
    local choiceGui, listBoxItems, game, listControl, btnConfirm, btnCancel, userChoicePath, oldDetectState

    choiceGui := Gui("+Owner" . myGui.Hwnd, "提示")
    choiceGui.SetFont(, "Microsoft YaHei UI")

    choiceGui.Add("Text", "x20 y15 w410 h25", "选择 AION2 " . currentServer.name . "安装目录：")

    listBoxItems := []
    for game in validGames {
        listBoxItems.Push("[" . game.softwareDisplayName . "] -> " . game.gameInstallPath)
    }

    listControl := choiceGui.Add("ListBox", "x20 y45 w410 h130 r5 Choose1 +HScroll", listBoxItems)
    btnConfirm := choiceGui.Add("Button", "x262 y190 w84 h30 Default", "确认")
    btnCancel := choiceGui.Add("Button", "x356 y190 w74 h30 ", "取消")

    userChoicePath := ""

    btnConfirm.OnEvent("Click", (*) => (userChoicePath := validGames[listControl.Value].gameInstallPath, myGui.Opt(
        "-Disabled"), choiceGui.Hide()))
    btnCancel.OnEvent("Click", (*) => (userChoicePath := "", myGui.Opt("-Disabled"), choiceGui.Hide()))
    choiceGui.OnEvent("Close", (*) => (userChoicePath := "", myGui.Opt("-Disabled"), choiceGui.Hide()))

    myGui.Opt("+Disabled")
    choiceGui.Show("w450 h240")

    oldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows False

    WinWaitClose(choiceGui)

    DetectHiddenWindows oldDetectState

    choiceGui.Destroy()
    RefreshUI()
    return userChoicePath
}

; 重置目录
DoReset(*) {
    global installPath, sectionName, pathEdit, configCache, currentServer

    pathEdit.Value := ""
    installPath := ""

    configCache.%sectionName%.installPath := ""
    configCache.%sectionName%.isManualReset := 1

    SaveAllConfig()

    ShowStatus("AION2 " . currentServer.name . "安装目录已重置。")
    RefreshUI()
}

; 一键汉化
DoChinese(*) {
    global installPath, currentServer
    local currentDestFiles, targetFullPath, hasAnyPatch, targetDir, statusMessage

    if (!installPath || !DirExist(installPath)) {
        ShowStatus("未设置 AION2 安装目录。")
        RefreshUI()
        return
    }

    currentDestFiles := []
    if (currentServer.id = 101) {
        currentDestFiles.Push(installPath . "\Aion2\Content\Paks\L10N\Text\en-US\pakchunk999999-Windows_999_P.pak")
        currentDestFiles.Push(installPath . "\Aion2\Binaries\Win64\dxgi.dll")
    } else if (currentServer.id = 102) {
        currentDestFiles.Push(installPath . "\Aion2\Content\Paks\L10N\Text\zh-TW\pakchunk504000-Windows_9999_P.pak")
    }

    hasAnyPatch := false
    for targetFullPath in currentDestFiles {
        if (FileExist(targetFullPath)) {
            hasAnyPatch := true
            break
        }
    }

    if (hasAnyPatch && !ConfirmAction()) {
        return
    }

    if (currentServer.id = 101) {
        try {
            for targetFullPath in currentDestFiles {
                SplitPath(targetFullPath, , &targetDir)
                if (!DirExist(targetDir)) {
                    DirCreate(targetDir)
                }
            }

            FileInstall("D:\Program Files\AutoHotkey\pakchunk999999-Windows_999_P.Pak", installPath .
                "\Aion2\Content\Paks\L10N\Text\en-US\pakchunk999999-Windows_999_P.pak", 1)
            FileInstall("D:\Program Files\AutoHotkey\dxgi.dll", installPath . "\Aion2\Binaries\Win64\dxgi.dll", 1)
        } catch {
            PopupPrompt("释放" . currentServer.name . "汉化文件时发生未知错误，汉化失败。")
            return
        }
    } else if (currentServer.id = 102) {
        try {
            for targetFullPath in currentDestFiles {
                SplitPath(targetFullPath, , &targetDir)
                if (!DirExist(targetDir)) {
                    DirCreate(targetDir)
                }
            }

            FileInstall("D:\Program Files\AutoHotkey\pakchunk504000-Windows_9999_P.Pak", installPath .
                "\Aion2\Content\Paks\L10N\Text\zh-TW\pakchunk504000-Windows_9999_P.pak", 1)
        } catch {
            PopupPrompt("释放" . currentServer.name . "汉化文件时发生未知错误，汉化失败。")
            return
        }
    }

    statusMessage := WinExist("AION2 ahk_exe Aion2.exe") ? "AION2 已成功汉化，重启 AION2 后生效。" : "AION2 已成功汉化。"
    ShowStatus(statusMessage)
}

; 撤销还原
DoRestore(*) {
    global installPath, currentServer
    local currentDestFiles, targetFullPath, hasAnyPatch, fileBaseName, statusMessage

    if (!installPath) {
        ShowStatus("未设置 AION2 安装目录。")
        RefreshUI()
        return
    }

    currentDestFiles := []
    if (currentServer.id = 101) {
        currentDestFiles.Push(installPath . "\Aion2\Content\Paks\L10N\Text\en-US\pakchunk999999-Windows_999_P.pak")
        currentDestFiles.Push(installPath . "\Aion2\Binaries\Win64\dxgi.dll")
    } else if (currentServer.id = 102) {
        currentDestFiles.Push(installPath . "\Aion2\Content\Paks\L10N\Text\zh-TW\pakchunk504000-Windows_9999_P.pak")
    }

    hasAnyPatch := false
    for targetFullPath in currentDestFiles {
        if (FileExist(targetFullPath)) {
            hasAnyPatch := true
            break
        }
    }

    if (!hasAnyPatch) {
        ShowStatus("未发现 AION2 " . currentServer.name . "汉化文件。")
        return
    }

    for targetFullPath in currentDestFiles {
        if (FileExist(targetFullPath)) {
            try {
                FileDelete(targetFullPath)
            } catch {
                SplitPath(targetFullPath, &fileBaseName)
                PopupPrompt("删除汉化文件失败，撤销操作中断。`r`n无法删除：" . fileBaseName)
                return
            }
        }
    }

    statusMessage := WinExist("AION2 ahk_exe Aion2.exe") ? "AION2 汉化已撤销，重启 AION2 后生效。" : "AION2 汉化已撤销。"
    ShowStatus(statusMessage)
}

; 更新须知文本提示
UpdateNoticeText() {
    global noticeControl, currentServer
    local ruleText := ""

    ruleText .= "1. 选择 AION2 " . currentServer.name . "的安装目录，"
    ruleText .= (currentServer.id = 102) ? "例如 D:\Games\AION2_TW。" : "例如 D:\Games\AION 2。"

    noticeControl.Value := ruleText .
        "`r`n2. 汉化完成后启动或重启 AION2，使汉化文件生效。" .
        "`r`n3. 如发生异常问题，使用“撤销”功能，或在 PURPLE 或 Steam 进行修复" .
        "`r`n   PURPLE : AION2 - 游戏设置 - 检查文件；" .
        "`r`n   Steam : AION2 -  属性 - 已安装的文件 - 验证游戏文件的完整性；" .
        "`r`n4. 汉化文件来自网游加速器，本工具为第三方扩展，使用即代表您知悉并自愿承担所有风险。"
}

; 临时渐隐状态栏输出
ShowStatus(statusMessage) {
    global statusBar
    statusBar.SetText("`t" . statusMessage)
    SetTimer(() => statusBar.SetText(""), -3000)
}

; 按钮核心焦点与状态刷新
RefreshUI() {
    global pathEdit, btnChinese, btnBrowse, btnReset
    if (pathEdit.Value) {
        btnReset.Enabled := true
        btnChinese.Focus()
    } else {
        btnReset.Enabled := false
        btnBrowse.Focus()
    }
}

; 覆盖文件确认弹窗
ConfirmAction() {
    global myGui
    local confirmGui, replyStatus, btnConfirm, btnCancel, oldDetectState

    confirmGui := Gui("+Owner" . myGui.Hwnd, "提示")
    confirmGui.SetFont(, "Microsoft YaHei UI")

    confirmGui.Add("Text", "x20 y20 h25", "检测到汉化文件，是否覆盖？")
    btnConfirm := confirmGui.Add("Button", "x182 y125 w84 h28", "确认")
    btnCancel := confirmGui.Add("Button", "x272 y125 w68 h28 Default", "取消")

    replyStatus := false

    btnConfirm.OnEvent("Click", (*) => (replyStatus := true, myGui.Opt("-Disabled"), confirmGui.Hide()))
    btnCancel.OnEvent("Click", (*) => (replyStatus := false, myGui.Opt("-Disabled"), confirmGui.Hide()))
    confirmGui.OnEvent("Close", (*) => (replyStatus := false, myGui.Opt("-Disabled"), confirmGui.Hide()))

    myGui.Opt("+Disabled")
    confirmGui.Show("w350 h166")

    oldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows False

    WinWaitClose(confirmGui)

    DetectHiddenWindows oldDetectState

    confirmGui.Destroy()
    RefreshUI()
    return replyStatus
}

; 阻断式警告提示弹窗
PopupPrompt(text) {
    global myGui
    local confirmGui, btnConfirm, oldDetectState

    confirmGui := Gui("+Owner" . myGui.Hwnd, "提示")
    confirmGui.SetFont(, "Microsoft YaHei UI")

    confirmGui.Add("Text", "x20 y20 w310 h110", text)
    btnConfirm := confirmGui.Add("Button", "x272 y125 w68 h28 Default", "确认")

    btnConfirm.OnEvent("Click", (*) => (myGui.Opt("-Disabled"), confirmGui.Hide()))
    confirmGui.OnEvent("Close", (*) => (myGui.Opt("-Disabled"), confirmGui.Hide()))

    myGui.Opt("+Disabled")
    confirmGui.Show("w350 h166")

    oldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows False

    WinWaitClose(confirmGui)

    DetectHiddenWindows oldDetectState

    confirmGui.Destroy()
    RefreshUI()
}

; 将持久化变量写入配置文件
SaveAllConfig() {
    global configFile, configCache, servers
    local server, loopSectionName

    IniWrite(configCache.Settings.LastServerID, configFile, "Settings", "LastServerID")
    for server in servers {
        loopSectionName := "Server_" . server.id
        IniWrite(configCache.%loopSectionName%.installPath, configFile, loopSectionName, "installPath")
        IniWrite(configCache.%loopSectionName%.isManualReset, configFile, loopSectionName, "isManualReset")
    }
}

; 游戏注册表扫描核心函数
ScanRegistryForGamePaths(keywordArray) {
    local matchedGameList, systemUninstallRoot, userUninstallRoot, currentFullKey, currentDisplayName, keyword,
        currentInstallPath, isDuplicatePath, existingGame, displayKeyString

    matchedGameList := []
    systemUninstallRoot := "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    userUninstallRoot := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall"

    SetRegView 64
    loop reg, systemUninstallRoot, "K" {
        currentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        currentDisplayName := RegRead(currentFullKey, "DisplayName", "")

        for keyword in keywordArray {
            if (InStr(currentDisplayName, keyword)) {
                currentInstallPath := RegRead(currentFullKey, "InstallLocation", "")
                if (currentInstallPath != "") {
                    isDuplicatePath := false
                    for existingGame in matchedGameList {
                        if (existingGame.gameInstallPath = currentInstallPath) {
                            isDuplicatePath := true
                            break
                        }
                    }
                    if (!isDuplicatePath) {
                        matchedGameList.Push({
                            fullRegistryPath: currentFullKey,
                            registryKeyName: A_LoopRegName,
                            softwareDisplayName: currentDisplayName,
                            gameInstallPath: currentInstallPath
                        })
                    }
                }
            }
        }
    }

    SetRegView 32
    loop reg, systemUninstallRoot, "K" {
        currentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        currentDisplayName := RegRead(currentFullKey, "DisplayName", "")

        for keyword in keywordArray {
            if (InStr(currentDisplayName, keyword)) {
                currentInstallPath := RegRead(currentFullKey, "InstallLocation", "")
                if (currentInstallPath != "") {
                    isDuplicatePath := false
                    for existingGame in matchedGameList {
                        if (existingGame.gameInstallPath = currentInstallPath) {
                            isDuplicatePath := true
                            break
                        }
                    }
                    if (!isDuplicatePath) {
                        displayKeyString := StrReplace(currentFullKey, "SOFTWARE\", "SOFTWARE\WOW6432Node\")
                        matchedGameList.Push({
                            fullRegistryPath: displayKeyString,
                            registryKeyName: A_LoopRegName,
                            softwareDisplayName: currentDisplayName,
                            gameInstallPath: currentInstallPath
                        })
                    }
                }
            }
        }
    }

    SetRegView "Default"
    loop reg, userUninstallRoot, "K" {
        currentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        currentDisplayName := RegRead(currentFullKey, "DisplayName", "")

        for keyword in keywordArray {
            if (InStr(currentDisplayName, keyword)) {
                currentInstallPath := RegRead(currentFullKey, "InstallLocation", "")
                if (currentInstallPath != "") {
                    isDuplicatePath := false
                    for existingGame in matchedGameList {
                        if (existingGame.gameInstallPath = currentInstallPath) {
                            isDuplicatePath := true
                            break
                        }
                    }
                    if (!isDuplicatePath) {
                        matchedGameList.Push({
                            fullRegistryPath: currentFullKey,
                            registryKeyName: A_LoopRegName,
                            softwareDisplayName: currentDisplayName,
                            gameInstallPath: currentInstallPath
                        })
                    }
                }
            }
        }
    }

    return matchedGameList
}
