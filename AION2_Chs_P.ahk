#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName AION2_Chs Patch
;@Ahk2Exe-SetOrigFilename AION2_Chs_P.exe
;@Ahk2Exe-SetProductName AION2 Chs Patch
;@Ahk2Exe-SetDescription AION2 一键汉化工具
;@Ahk2Exe-SetVersion 1.1.0.0
;@Ahk2Exe-SetCopyright Copyright © 2026
;@Ahk2Exe-SetMainIcon AutoHotkey\icon.ico
#Include ".\AutoHotkey\lib\UniqueInstance.ahk"
#Include ".\AutoHotkey\lib\PathUtil.ahk"
#Include ".\AutoHotkey\Lib\WinHttpRequest.ahk"
#Include ".\AutoHotkey\lib\JSON.ahk"

#NoTrayIcon
Persistent true
#SingleInstance Off

; 权限与单例预检
UiResult := UniqueInstance.Ensure(Map(
    "preferRunAsAdmin", true,
    "allowCoexist", true,
    "showReport", true
))

; ==============================================================================
; 1. 核心数据源（全局变量 - 单一数据源 SSOT）
; ==============================================================================
global g_GlobalConfigData := Map()
global g_ClientUpdateData := Map()
global g_ServersConfigData := []
global g_CloudBulletinData := Map()

; 基础运行参数与配置项
global g_ConfigFile := "config.ini"
global g_CurrentAppVersion := "1.1.0.0"
global g_LastSeenBulletinVersion := ""

global g_DefaultPreUrl := "https://raw.githubusercontent.com/nanhezzb/Aion2-Chinese-Patch/refs/heads/main"
global g_DefaultProxyMirrors := [
    "https://gh-proxy.com"
]

global g_AppManifestFilename := "app_manifest.json"
global g_PatchManifestFilename := "patch_manifest.json"

global g_CleanPreUrl := RTrim(g_DefaultPreUrl, "/")
global g_CleanProxyMirrors := []
global g_CleanRemoteAppUrl := ""
global g_CleanRemotePatchUrl := ""

global g_RequestTimeoutSeconds := 30

global g_DefaultServers := [
    Map(
        "id", 102,
        "name", "台服",
        "display", "台服 - PURPLE",
        "keywords", [
            "AION"
        ],
        "patch_branches", [
            Map(
                "id", 1,
                "source", "xy",
                "latest_patch_version", "1.0.0.0",
                "changelog", "",
                "release_timestamp", 1789981021,
                "actions", [
                    Map(
                        "type", "add",
                        "remote_filename", "patchs/xy_pakchunk504000-Windows_9999_P.pak",
                        "target_relative_path",
                        "Aion2\\Content\\Paks\\L10N\\Text\\zh-TW\\pakchunk504000-Windows_9999_P.pak",
                        "file_md5", "d8f909cef6c96595e0e3514ed0e744da",
                        "file_size", 3672850
                    )
                ]
            )
        ]
    )
]

; 界面状态与控制变量
global g_IsDialogShowing := false
global g_IsLocalInitComplete := false
global g_InstallPath := ""
global g_PatchsCacheDir := "patchs"

global g_BestDownloadPrefix := ""
global g_BestLatency := 99999

global g_ConfigCache := {
    Settings: {
        LastServerID: 102
    }
}

global g_CurrentServer := Map()

; 初始化数据源兜底值
g_ServersConfigData := g_DefaultServers
InitProxyMirrors(g_DefaultProxyMirrors)

; ==============================================================================
; 2. GUI 布局初始化
; ==============================================================================
global MainGui := Gui(, "AION2 一键汉化工具 1.0")
MainGui.SetFont("s9", "Microsoft YaHei")

global TabCtrl := MainGui.AddTab3("x-1 y10 w574 h460", [
    "中文汉化",
    "免费加速器"
])

; --- Tab 1 ---
TabCtrl.UseTab(1)
MainGui.AddGroupBox("x17 y45 w536 h75", " 选择服务器 * ")
global ComboServerList := MainGui.AddDropDownList("x27 y75 w516 Choose1", [])

MainGui.AddGroupBox("x17 y130 w536 h115", " 选择安装目录 * ")
global EditInstallPath := MainGui.AddEdit("x27 y160 w516 r1 ReadOnly", "")
global BtnScan := MainGui.AddButton("x345 y201 w65 h26", "查找")
global BtnBrowse := MainGui.AddButton("x417 y201 w60 h26", "浏览...")
global BtnReset := MainGui.AddButton("x484 y201 w60 h26 +Disabled", "重置")

MainGui.AddGroupBox("x17 y255 w536 h145", "使用须知 * ")
global TextExplain := MainGui.AddText("x31 y280 w510 h105", "")

global BtnChinese := MainGui.AddButton("x182 y418 w100 h32", "一键汉化")
global BtnRestore := MainGui.AddButton("x289 y418 w100 h32", "撤销汉化")

; --- Tab 2 ---
TabCtrl.UseTab(2)
MainGui.AddLink("x31 y75 w510 r1", '<a href="https://www.ggkuai.com/">古怪加速器 - 每天0-16点免费，极速稳定全球网游加速。</a>')
MainGui.AddLink("x31 y100 w510 r1",
    '<a href="https://www.akspeedy.com/html/invite_new/invite_download.html?inviter=3Xtkus4t">AK加速器- 每天0-14点免费，支持全球网游加速。</a>'
)
MainGui.AddLink("x31 y125 w510 r1",
    '<a href="https://www.xiaoyao.co/index.htm">逍遥加速器 - 24小时免费加速，全新模式 - 平台加速。支持 Steam、EA、Epic、暴雪等平台。</a>')

TabCtrl.UseTab(0)
global MainStatusBar := MainGui.AddStatusBar(, "")

; 绑定 UI 事件
ComboServerList.OnEvent("Change", (*) => SelectServer())
BtnScan.OnEvent("Click", (*) => OnScanButtonClick())
BtnBrowse.OnEvent("Click", BrowseFolder)
BtnReset.OnEvent("Click", DoResetConfig)
BtnChinese.OnEvent("Click", DoChinesePatch)
BtnRestore.OnEvent("Click", DoRestorePatch)
MainGui.OnEvent("Close", (*) => ExitApp())

; 启动主程序
InitializeApp()

; ==============================================================================
; 3. 单一数据源（SSOT）解析与分发中枢
; ==============================================================================
ParseAndApplyManifest(JsonContent, IsPatchFile := false) {
    global g_ClientUpdateData, g_ServersConfigData, g_CloudBulletinData, g_GlobalConfigData

    try {
        Parsed := JSON.parse(JsonContent)
        if (Type(Parsed) != "Map")
            return false

        if (Parsed.Has("client_update") && Type(Parsed["client_update"]) == "Map") {
            g_ClientUpdateData := Parsed["client_update"]
        }

        if (IsPatchFile && Parsed.Has("servers_config") && Type(Parsed["servers_config"]) == "Array" && Parsed[
            "servers_config"].Length > 0) {
            g_ServersConfigData := Parsed["servers_config"]
        }

        if (IsPatchFile && Parsed.Has("cloud_bulletin") && Type(Parsed["cloud_bulletin"]) == "Map") {
            g_CloudBulletinData := Parsed["cloud_bulletin"]
        }

        if (Parsed.Has("global_config") && Type(Parsed["global_config"]) == "Map") {
            g_GlobalConfigData := Parsed["global_config"]
            ApplyGlobalConfig()
        }

        return true
    } catch {
        return false
    }
}

; ==============================================================================
; 4. 本地加载与云端同步闭环
; ==============================================================================

InitializeApp() {
    global g_IsLocalInitComplete, MainGui
    MainGui.Show("w570 h490")
    ShowStatus("正在初始化本地环境...")

    LoadLocalManifests()
    ReadConfig()
    UpdateGlobalUrls()

    g_IsLocalInitComplete := true
    ShowStatus("本地数据就绪。")
    SetTimer(StartCloudSync, -300)
}

LoadLocalManifests() {
    global g_AppManifestFilename, g_PatchManifestFilename, g_ServersConfigData, g_DefaultServers, g_DefaultProxyMirrors

    if FileExist(g_AppManifestFilename) {
        try {
            Content := FileRead(g_AppManifestFilename, "UTF-8")
            ParseAndApplyManifest(Content, false)
        } catch {
        }
    }

    if FileExist(g_PatchManifestFilename) {
        try {
            Content := FileRead(g_PatchManifestFilename, "UTF-8")
            if (!ParseAndApplyManifest(Content, true)) {
                g_ServersConfigData := g_DefaultServers
                InitProxyMirrors(g_DefaultProxyMirrors)
            }
        } catch {
            g_ServersConfigData := g_DefaultServers
            InitProxyMirrors(g_DefaultProxyMirrors)
        }
    } else {
        g_ServersConfigData := g_DefaultServers
        InitProxyMirrors(g_DefaultProxyMirrors)
    }
}

StartCloudSync() {
    global g_ConfigFile, g_RequestTimeoutSeconds, g_IsLocalInitComplete, g_IsDialogShowing,
        g_CloudBulletinData, g_ClientUpdateData

    if (!g_IsLocalInitComplete)
        return

    ShowStatus("正在后台拉取云端最新配置...")

    IsSyncSuccess := SyncCloudConfig()

    if (IsSyncSuccess) {
        CurrentTimestamp := DateDiff(A_NowUTC, "19700101000000", "Seconds")
        IniWrite(CurrentTimestamp, g_ConfigFile, "Settings", "LastCheckTime")
        IniWrite(g_RequestTimeoutSeconds, g_ConfigFile, "Settings", "RequestTimeoutSeconds")

        if (!g_IsDialogShowing) {
            SafeRefreshUi()
            ShowStatus("云端配置同步成功，已保存至本地。")
        } else {
            ShowStatus("云端配置已保存至本地 (等待下次启动生效)。")
        }
    } else {
        ShowStatus("连接超时或离线：已加载本地保存配置。")
    }

    if (Type(g_ClientUpdateData) == "Map" && g_ClientUpdateData.Count > 0) {
        CheckAppUpdate(g_ClientUpdateData)
    }

    if (Type(g_CloudBulletinData) == "Map" && g_CloudBulletinData.Count > 0) {
        CheckBulletin(g_CloudBulletinData)
    }
}

SyncCloudConfig() {
    global g_AppManifestFilename, g_PatchManifestFilename, g_RequestTimeoutSeconds, g_CleanRemoteAppUrl,
        g_CleanRemotePatchUrl

    IsAppSuccess := false
    IsPatchSuccess := false

    AppJson := HttpGetText(g_CleanRemoteAppUrl, g_RequestTimeoutSeconds)
    if (AppJson != "") {
        if (ParseAndApplyManifest(AppJson, false)) {
            WriteFileAtomic(g_AppManifestFilename, AppJson)
            IsAppSuccess := true
        }
    }

    PatchJson := HttpGetText(g_CleanRemotePatchUrl, g_RequestTimeoutSeconds)
    if (PatchJson != "") {
        if (ParseAndApplyManifest(PatchJson, true)) {
            WriteFileAtomic(g_PatchManifestFilename, PatchJson)
            IsPatchSuccess := true
        }
    }

    return (IsAppSuccess || IsPatchSuccess)
}

; ==============================================================================
; 5. UI 与业务逻辑消费
; ==============================================================================

ApplyGlobalConfig() {
    global g_GlobalConfigData, g_RequestTimeoutSeconds
    if (g_GlobalConfigData.Has("download_timeout_seconds"))
        g_RequestTimeoutSeconds := Number(g_GlobalConfigData["download_timeout_seconds"])
    if (g_GlobalConfigData.Has("proxy_mirrors") && Type(g_GlobalConfigData["proxy_mirrors"]) == "Array")
        InitProxyMirrors(g_GlobalConfigData["proxy_mirrors"])
}

InitProxyMirrors(MirrorsArray) {
    global g_CleanProxyMirrors
    g_CleanProxyMirrors := []
    for Mirror in MirrorsArray {
        if (Mirror != "")
            g_CleanProxyMirrors.Push(RTrim(Mirror, "/"))
    }
}

UpdateGlobalUrls() {
    global g_CleanPreUrl, g_AppManifestFilename, g_PatchManifestFilename, g_CleanRemoteAppUrl, g_CleanRemotePatchUrl
    TimestampParam := "?t=" . DateDiff(A_NowUTC, "19700101000000", "Seconds")

    g_CleanRemoteAppUrl := g_CleanPreUrl . "/" . g_AppManifestFilename . TimestampParam
    g_CleanRemotePatchUrl := g_CleanPreUrl . "/" . g_PatchManifestFilename . TimestampParam
}

ReadConfig() {
    global g_ConfigCache, g_ConfigFile, g_ServersConfigData, g_LastSeenBulletinVersion

    g_LastSeenBulletinVersion := IniRead(g_ConfigFile, "Settings", "LastSeenBulletinVersion", "")

    for Server in g_ServersConfigData {
        SectionName := "Server_" . Server["id"]
        g_ConfigCache.%SectionName% := {
            InstallPath: IniRead(g_ConfigFile, SectionName, "install_path", ""),
            IsManualReset: Number(IniRead(g_ConfigFile, SectionName, "is_manual_reset", 0))
        }
    }

    RefreshServerComboBox()
}

RefreshServerComboBox() {
    global g_ServersConfigData, ComboServerList, g_ConfigFile, g_CurrentServer, g_ConfigCache

    DropDownOptions := []
    SavedLastId := Number(IniRead(g_ConfigFile, "Settings", "LastServerID", "102"))
    TargetIndex := 1

    loop g_ServersConfigData.Length {
        Server := g_ServersConfigData[A_Index]
        DisplayTxt := Server.Has("display") ? Server["display"] : Server["name"]
        DropDownOptions.Push(DisplayTxt)
        if (Server["id"] == SavedLastId)
            TargetIndex := A_Index
    }

    ComboServerList.Delete()
    ComboServerList.Add(DropDownOptions)
    ComboServerList.Value := TargetIndex

    if (g_ServersConfigData.Length >= TargetIndex) {
        g_CurrentServer := g_ServersConfigData[TargetIndex]
        g_ConfigCache.Settings.LastServerID := g_CurrentServer["id"]
    }

    RefreshServerData()
    if (g_InstallPath == "")
        SilentDetectFolder()
}

RefreshServerData() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath

    if (!g_CurrentServer || !g_CurrentServer.Has("id"))
        return

    SectionName := "Server_" . g_CurrentServer["id"]

    UpdateNoticeText()

    if (!g_ConfigCache.HasOwnProp(SectionName)) {
        g_ConfigCache.%SectionName% := {
            InstallPath: "",
            IsManualReset: 0
        }
    }

    SavedPath := g_ConfigCache.%SectionName%.InstallPath
    if (SavedPath != "") {
        if (DirExist(SavedPath) && FileExist(SavedPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            g_InstallPath := SavedPath
            EditInstallPath.Value := SavedPath
        } else {
            g_InstallPath := ""
            EditInstallPath.Value := ""
            g_ConfigCache.%SectionName%.InstallPath := ""
            SaveAllConfig()
            ShowMessageDialog("无效的目录地址，安装目录已重置。")
        }
    } else {
        g_InstallPath := ""
        EditInstallPath.Value := ""
    }

    RefreshUi()
}

RefreshUi() {
    global BtnBrowse, BtnChinese, BtnReset, EditInstallPath
    if (EditInstallPath.Value) {
        BtnReset.Enabled := true
        BtnChinese.Focus()
    } else {
        BtnReset.Enabled := false
        BtnScan.Focus()
    }
}

SafeRefreshUi() {
    global g_IsDialogShowing, MainGui
    if (g_IsDialogShowing || !WinExist(MainGui))
        return

    RefreshServerComboBox()
    RefreshServerData()
}

SelectServer() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, ComboServerList, g_ServersConfigData
    g_CurrentServer := g_ServersConfigData[ComboServerList.Value]
    g_ConfigCache.Settings.LastServerID := g_CurrentServer["id"]
    SaveAllConfig()

    RefreshServerData()
    ShowStatus("已切换至 " . g_CurrentServer["name"] . " 配置。")

    if (g_InstallPath == "")
        SilentDetectFolder()
}

SaveAllConfig() {
    global g_ConfigCache, g_ConfigFile, g_ServersConfigData, g_LastSeenBulletinVersion
    IniWrite(g_ConfigCache.Settings.LastServerID, g_ConfigFile, "Settings", "LastServerID")
    IniWrite(g_LastSeenBulletinVersion, g_ConfigFile, "Settings", "LastSeenBulletinVersion")
    for Server in g_ServersConfigData {
        SectionName := "Server_" . Server["id"]
        if (g_ConfigCache.HasOwnProp(SectionName)) {
            IniWrite(g_ConfigCache.%SectionName%.InstallPath, g_ConfigFile, SectionName, "install_path")
            IniWrite(g_ConfigCache.%SectionName%.IsManualReset, g_ConfigFile, SectionName, "is_manual_reset")
        }
    }
}

; ==============================================================================
; 6. 汉化与还原核心业务逻辑
; ==============================================================================

DoChinesePatch(*) {
    global g_InstallPath, g_CurrentServer, g_ConfigFile, g_PatchsCacheDir, BtnChinese

    BtnChinese.Opt("+Disabled")

    try {
        if (!g_InstallPath || !DirExist(g_InstallPath)) {
            ShowStatus("请先设置 AION2 安装目录。")
            ShowMessageDialog("请先设置 AION2 游戏的安装目录！")
            return
        }

        if (!g_CurrentServer.Has("patch_branches") || Type(g_CurrentServer["patch_branches"]) != "Array" ||
        g_CurrentServer["patch_branches"].Length == 0) {
            ShowMessageDialog("当前服务器配置中未发现有效的汉化补丁分支。")
            return
        }

        PatchBranch := g_CurrentServer["patch_branches"][1]
        if (!PatchBranch.Has("actions") || Type(PatchBranch["actions"]) != "Array") {
            ShowMessageDialog("当前汉化分支内未配置具体的文件释放动作。")
            return
        }

        ActionsArray := PatchBranch["actions"]

        HasAnyInstalled := false
        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            TargetFilePath := PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])
            if (FileExist(TargetFilePath)) {
                HasAnyInstalled := true
                break
            }
        }

        if (HasAnyInstalled) {
            if (!ShowConfirmDialog("检测到游戏目录中已存在汉化补丁文件，是否直接覆盖更新？")) {
                return
            }
        }

        if !DirExist(g_PatchsCacheDir)
            DirCreate(g_PatchsCacheDir)

        TempDownloadList := Map()
        ShowStatus("正在检查本地 patchs 缓存目录中的文件指纹...")

        AllLocalCacheValid := true
        loop ActionsArray.Length {
            FileAction := ActionsArray[A_Index]
            RemoteFile := Trim(FileAction["remote_filename"])
            TargetMd5 := FileAction.Has("file_md5") ? String(FileAction["file_md5"]) : ""
            LocalCacheFile := PathUtil.Normalize(RemoteFile)

            if (!FileExist(LocalCacheFile) || TargetMd5 == "" || HashFileMd5(LocalCacheFile) != TargetMd5) {
                AllLocalCacheValid := false
                break
            }
        }

        if (!AllLocalCacheValid) {
            try {
                FindFastestDownloadNode()
            } catch Error as Err {
                ShowStatus("测速失败：" . Err.Message)
                ShowMessageDialog("测速失败：" . Err.Message)
                return
            }
        } else {
            ShowStatus("本地缓存全部校验通过，已跳过网络下载。")
        }

        loop ActionsArray.Length {
            FileAction := ActionsArray[A_Index]
            RemoteFile := Trim(FileAction["remote_filename"])
            TargetMd5 := FileAction.Has("file_md5") ? String(FileAction["file_md5"]) : ""
            LocalCacheFile := PathUtil.Normalize(RemoteFile)

            SplitPath(LocalCacheFile, , &LocalCacheDir)
            if (LocalCacheDir != "" && !DirExist(LocalCacheDir))
                DirCreate(LocalCacheDir)

            if (FileExist(LocalCacheFile) && TargetMd5 != "" && HashFileMd5(LocalCacheFile) == TargetMd5) {
                TempDownloadList[RemoteFile] := Map("src", LocalCacheFile, "fileAction", FileAction)
                continue
            }

            SafeFilename := RegExReplace(RemoteFile, '[\\/:*?"<>|]', "_")
            TmpFile := PathUtil.Normalize(A_Temp . "\" . SafeFilename . ".tmp")

            if FileExist(TmpFile) {
                try FileDelete(TmpFile)
            }

            DownloadSuccess := DownloadSingleFileWithNode(RemoteFile, TmpFile, FileAction)

            if (!DownloadSuccess) {
                if FileExist(TmpFile)
                    FileDelete(TmpFile)
                throw Error("补丁文件 [" . RemoteFile . "] 下载失败！")
            }

            if (TargetMd5 != "" && HashFileMd5(TmpFile) != TargetMd5) {
                if FileExist(TmpFile)
                    FileDelete(TmpFile)
                throw Error("文件 [" . RemoteFile . "] 指纹不匹配，可能遭节点缓存损坏。")
            }

            if FileExist(LocalCacheFile)
                FileDelete(LocalCacheFile)
            FileMove(TmpFile, LocalCacheFile, 1)

            ShowStatus("文件 [" . RemoteFile . "] 下载并校验完成。")
            TempDownloadList[RemoteFile] := Map("src", LocalCacheFile, "fileAction", FileAction)
        }

        ShowStatus("校验通过！正在应用补丁文件到游戏目录...")

        TargetVersion := PatchBranch.Has("latest_patch_version") ? Trim(PatchBranch["latest_patch_version"]) :
            "1.0.0.0"
        IniWrite(TargetVersion, g_ConfigFile, "Server_" . g_CurrentServer["id"], "local_patch_version")

        for RemoteFile, Info in TempDownloadList {
            Act := Info["fileAction"]
            FinalDestPath := PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])

            SplitPath(FinalDestPath, , &FDir)
            if (FDir != "" && !DirExist(FDir))
                DirCreate(FDir)

            FileCopy(Info["src"], FinalDestPath, 1)
        }

        ShowStatus("汉化完成")
        ShowMessageDialog("汉化完成！补丁文件已成功释放至游戏目录。")

    } catch Error as Err {
        ShowStatus("汉化中断：" . Err.Message)
        ShowMessageDialog("汉化失败：`r`n" . Err.Message)
    } finally {
        BtnChinese.Opt("-Disabled")
    }
}

DoRestorePatch(*) {
    global g_InstallPath, g_CurrentServer, g_ConfigFile, BtnRestore

    BtnRestore.Opt("+Disabled")

    try {
        if (!g_InstallPath || !DirExist(g_InstallPath)) {
            ShowStatus("请先设置 AION2 安装目录。")
            ShowMessageDialog("请先设置 AION2 游戏的安装目录！")
            return
        }

        if (!g_CurrentServer.Has("patch_branches") || Type(g_CurrentServer["patch_branches"]) != "Array" ||
        g_CurrentServer["patch_branches"].Length == 0) {
            ShowStatus("无可撤销的补丁分支。")
            return
        }

        PatchBranch := g_CurrentServer["patch_branches"][1]
        if (!PatchBranch.Has("actions") || Type(PatchBranch["actions"]) != "Array") {
            ShowStatus("无可撤销的动作列表。")
            return
        }

        ActionsArray := PatchBranch["actions"]

        HasAnyPatchFile := false
        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            FinalDestPath := PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])
            if FileExist(FinalDestPath) {
                HasAnyPatchFile := true
                break
            }
        }

        if (!HasAnyPatchFile) {
            ShowStatus("未发现汉化文件")
            ShowMessageDialog("未发现汉化文件，无需执行撤销操作！")
            return
        }

        ShowStatus("正在清除汉化残留物理文件...")

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            FinalDestPath := PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])

            if FileExist(FinalDestPath) {
                FileDelete(FinalDestPath)
                if FileExist(FinalDestPath)
                    throw Error("文件被未知进程占用锁死，清除失败。")
            }
        }

        IniWrite("", g_ConfigFile, "Server_" . g_CurrentServer["id"], "local_patch_version")
        ShowStatus("还原完成")
        ShowMessageDialog("撤销成功！汉化文件已删除。")

    } catch Error as Err {
        ShowStatus("撤销中断：" . Err.Message)
        ShowMessageDialog("撤销失败：`r`n" . Err.Message)
    } finally {
        BtnRestore.Opt("-Disabled")
    }
}

DoResetConfig(*) {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath
    SectionName := "Server_" . g_CurrentServer["id"]

    EditInstallPath.Value := ""
    g_InstallPath := ""
    g_ConfigCache.%SectionName%.InstallPath := ""
    g_ConfigCache.%SectionName%.IsManualReset := 1

    SaveAllConfig()
    ShowStatus("AION2 " . g_CurrentServer["name"] . "安装目录已重置。")
    RefreshUi()
}

BrowseFolder(*) {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath
    SectionName := "Server_" . g_CurrentServer["id"]

    PromptText := "选择 AION2 " . g_CurrentServer["name"] . "安装目录："
    SelectedFolder := FileSelect("D", EditInstallPath.Value, PromptText)

    if (SelectedFolder = "")
        return

    NormalizedSelectedFolder := PathUtil.Normalize(SelectedFolder)
    if (!FileExist(NormalizedSelectedFolder . "\Aion2\Binaries\Win64\Aion2.exe")) {
        ShowMessageDialog("所选目录中未检测主程序 Aion2.exe，请重新选择正确的安装目录。")
        return
    }

    EditInstallPath.Value := NormalizedSelectedFolder
    g_InstallPath := NormalizedSelectedFolder
    g_ConfigCache.%SectionName%.InstallPath := NormalizedSelectedFolder
    g_ConfigCache.%SectionName%.IsManualReset := 0

    SaveAllConfig()
    ShowStatus("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
    RefreshUi()
}

; ==============================================================================
; 7. 测速与网络辅助模块
; ==============================================================================

GetUrlLatency(Url, TimeoutSeconds := 2) {
    StartTime := A_TickCount
    try {
        Whr := WinHttpRequest()
        Whr.Open("HEAD", Url, true)
        Whr.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        Whr.Send()
        if (Whr.WaitForResponse(TimeoutSeconds)) {
            if (Whr.Status == 200 || Whr.Status == 301 || Whr.Status == 302) {
                return A_TickCount - StartTime
            }
        }
    } catch {
    }
    return 99999
}

FindFastestDownloadNode() {
    global g_CleanPreUrl, g_PatchManifestFilename, g_CleanProxyMirrors, MainStatusBar, g_BestDownloadPrefix,
        g_BestLatency

    ManifestPath := g_PatchManifestFilename

    Candidates := []
    Candidates.Push({
        Prefix: "",
        TestUrl: g_CleanPreUrl . "/" . ManifestPath
    })

    for Mirror in g_CleanProxyMirrors {
        Candidates.Push({
            Prefix: Mirror,
            TestUrl: Mirror . "/" . g_CleanPreUrl . "/" . ManifestPath
        })
    }

    MainStatusBar.SetText("`t正在对所有下载节点进行网络测速...")
    Sleep(50)

    BestNode := Candidates[1]
    g_BestLatency := 99999

    for Node in Candidates {
        Latency := GetUrlLatency(Node.TestUrl, 2)
        if (Latency < g_BestLatency) {
            g_BestLatency := Latency
            BestNode := Node
        }
    }

    if (g_BestLatency >= 99999) {
        throw Error("所有下载节点连接超时，请检查网络或开启加速器！")
    }

    g_BestDownloadPrefix := BestNode.Prefix
    return BestNode
}

DownloadSingleFileWithNode(RemoteFile, DestPath, FileAction := Map()) {
    global g_CleanPreUrl, g_BestDownloadPrefix, g_BestLatency, MainStatusBar

    CleanRemotePath := LTrim(RemoteFile, "/")

    if (g_BestDownloadPrefix != "") {
        TargetUrl := g_BestDownloadPrefix . "/" . g_CleanPreUrl . "/" . CleanRemotePath
    } else {
        TargetUrl := g_CleanPreUrl . "/" . CleanRemotePath
    }

    TotalBytes := (Type(FileAction) == "Map" && FileAction.Has("file_size")) ? FileAction["file_size"] : 0
    TotalSizeStr := (TotalBytes > 0) ? FormatFileSize(TotalBytes) : "未知大小"

    UpdateDownloadStatus() {
        try {
            CurrentBytes := FileExist(DestPath) ? FileGetSize(DestPath) : 0
            CurrentSizeStr := FormatFileSize(CurrentBytes)

            if (TotalBytes > 0) {
                StatusText := Format("`t正在下载：{} [{} / {}] (节点: {}ms)", RemoteFile, CurrentSizeStr, TotalSizeStr,
                    g_BestLatency)
            } else {
                StatusText := Format("`t正在下载：{} [{}] (节点: {}ms)", RemoteFile, CurrentSizeStr, g_BestLatency)
            }
            MainStatusBar.SetText(StatusText)
        }
    }

    SetTimer(UpdateDownloadStatus, 100)
    UpdateDownloadStatus()

    try {
        SplitPath(DestPath, , &ParentDir)
        if (ParentDir != "" && !DirExist(ParentDir))
            DirCreate(ParentDir)

        if FileExist(DestPath)
            FileDelete(DestPath)

        Download(TargetUrl, DestPath)
        SetTimer(UpdateDownloadStatus, 0)

        if (FileExist(DestPath) && FileGetSize(DestPath) > 0) {
            return true
        }
    } catch Error as Err {
        SetTimer(UpdateDownloadStatus, 0)
    }

    SetTimer(UpdateDownloadStatus, 0)
    return false
}

HttpGetText(ApiUrl, TimeoutSeconds) {
    global g_CleanProxyMirrors

    UrlQueue := []
    for Mirror in g_CleanProxyMirrors
        UrlQueue.Push(Mirror . "/" . LTrim(ApiUrl, "/"))
    UrlQueue.Push(ApiUrl)

    for TargetUrl in UrlQueue {
        try {
            Whr := WinHttpRequest()
            Whr.Open("GET", TargetUrl, true)
            Whr.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            Whr.Send()
            if (Whr.WaitForResponse(TimeoutSeconds)) {
                if (Whr.Status == 200)
                    return Whr.ResponseText
            }
        } catch {
            continue
        }
    }
    return ""
}

; ==============================================================================
; 8. 公告、更新弹窗与通用工具函数
; ==============================================================================

FormatFileSize(Bytes) {
    if (!IsNumber(Bytes) || Bytes <= 0)
        return "0 B"
    if (Bytes < 1024)
        return Bytes . " B"
    else if (Bytes < 1048576)
        return Format("{:.2f} KB", Bytes / 1024)
    else if (Bytes < 1073741824)
        return Format("{:.2f} MB", Bytes / 1048576)
    else
        return Format("{:.2f} GB", Bytes / 1073741824)
}

CheckAppUpdate(UpdateMap) {
    global g_CurrentAppVersion

    if (Type(UpdateMap) != "Map" || !UpdateMap.Has("latest_client_version"))
        return false

    LatestVersion := String(UpdateMap["latest_client_version"])
    MinRequiredVersion := UpdateMap.Has("min_required_version") ? String(UpdateMap["min_required_version"]) : ""
    ChangelogText := UpdateMap.Has("changelog") ? String(UpdateMap["changelog"]) : ""

    IsForceUpdate := (MinRequiredVersion != "" && VerCompare(MinRequiredVersion, g_CurrentAppVersion) > 0)
    HasNewVersion := (LatestVersion != "" && VerCompare(LatestVersion, g_CurrentAppVersion) > 0)

    if (IsForceUpdate || HasNewVersion) {
        DownloadUrlMain := UpdateMap.Has("client_download_url_main") ? String(UpdateMap["client_download_url_main"]) :
            ""
        DownloadUrlMinor := UpdateMap.Has("client_download_url_minor") ? String(UpdateMap["client_download_url_minor"]) :
            ""

        ShowAppUpdateDialog(ChangelogText, DownloadUrlMain, DownloadUrlMinor, IsForceUpdate)
        return true
    }
    return false
}

ShowAppUpdateDialog(ChangelogText, DownloadUrlMain, DownloadUrlMinor, IsForceUpdate := false) {
    global MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    UpdateGui := Gui("+Owner" . MainGui.Hwnd, "软件更新提示")
    UpdateGui.SetFont(, "Microsoft YaHei UI")

    UpdateGui.Add("Text", "x20 y20 w360", "当前软件版本过低，请下载最新版本后继续使用！")
    UpdateGui.Add("Edit", "x20 y45 w360 h150 ReadOnly", ChangelogText)

    BtnDownloadMain := UpdateGui.Add("Button", "x170 y225 w100 h30 Default", "主线路下载")
    BtnDownloadMinor := UpdateGui.Add("Button", "x280 y225 w100 h30", "备用下载")

    BtnDownloadMain.OnEvent("Click", (*) => (DownloadUrlMain != "" ? Run(DownloadUrlMain) : false))
    BtnDownloadMinor.OnEvent("Click", (*) => (DownloadUrlMinor != "" ? Run(DownloadUrlMinor) : false))

    OnClose(*) {
        if (IsForceUpdate) {
            ExitApp()
        } else {
            MainGui.Opt("-Disabled")
            UpdateGui.Hide()
        }
    }

    UpdateGui.OnEvent("Close", OnClose)
    UpdateGui.OnEvent("Escape", OnClose)

    MainGui.Opt("+Disabled")
    UpdateGui.Show("w400 h275")

    OldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows true
    WinWaitClose(UpdateGui)
    DetectHiddenWindows OldDetectState

    UpdateGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
}

CheckBulletin(BulletinMap) {
    global g_LastSeenBulletinVersion

    if (Type(BulletinMap) != "Map" || !BulletinMap.Has("latest_bulletin_version"))
        return

    LatestVersion := String(BulletinMap["latest_bulletin_version"])
    BulletinText := BulletinMap.Has("changelog") ? String(BulletinMap["changelog"]) : ""

    if (LatestVersion != "" && VerCompare(LatestVersion, g_LastSeenBulletinVersion) > 0 && BulletinText != "") {
        ShowBulletinDialog(BulletinText, LatestVersion)
    }
}

ShowBulletinDialog(ContentText, BulletinVersion) {
    global MainGui, g_IsDialogShowing, g_LastSeenBulletinVersion
    g_IsDialogShowing := true

    BulletinGui := Gui("+Owner" . MainGui.Hwnd, "最新公告")
    BulletinGui.SetFont(, "Microsoft YaHei UI")

    BulletinGui.Add("Edit", "x20 y20 w360 h150 ReadOnly -WantReturn", ContentText)

    BtnConfirm := BulletinGui.Add("Button", "x290 y200 w90 h30 Default", "我知道了")

    OnCloseOrConfirm(*) {
        g_LastSeenBulletinVersion := BulletinVersion
        SaveAllConfig()
        MainGui.Opt("-Disabled")
        BulletinGui.Hide()
    }

    BtnConfirm.OnEvent("Click", OnCloseOrConfirm)
    BulletinGui.OnEvent("Close", OnCloseOrConfirm)

    MainGui.Opt("+Disabled")
    BulletinGui.Show("w400 h250")

    OldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows true
    WinWaitClose(BulletinGui)
    DetectHiddenWindows OldDetectState

    BulletinGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
}

ShowConfirmDialog(Text) {
    global MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    ConfirmGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    ConfirmGui.SetFont(, "Microsoft YaHei UI")

    ConfirmGui.Add("Text", "x20 y20 w310 h60", Text)

    BtnConfirm := ConfirmGui.Add("Button", "x184 y102 w68 h28 Default", "确认")
    BtnCancel := ConfirmGui.Add("Button", "x262 y102 w68 h28", "取消")

    UserChoice := false
    BtnConfirm.OnEvent("Click", (*) => (UserChoice := true, MainGui.Opt("-Disabled"), ConfirmGui.Hide()))
    BtnCancel.OnEvent("Click", (*) => (UserChoice := false, MainGui.Opt("-Disabled"), ConfirmGui.Hide()))
    ConfirmGui.OnEvent("Close", (*) => (UserChoice := false, MainGui.Opt("-Disabled"), ConfirmGui.Hide()))

    MainGui.Opt("+Disabled")
    ConfirmGui.Show("w350 h150")

    OldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows true
    WinWaitClose(ConfirmGui)
    DetectHiddenWindows OldDetectState

    ConfirmGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
    return UserChoice
}

ShowMessageDialog(Text) {
    global MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    ConfirmGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    ConfirmGui.SetFont(, "Microsoft YaHei UI")

    ConfirmGui.Add("Text", "x20 y20 w310 h60", Text)

    BtnConfirm := ConfirmGui.Add("Button", "x262 y102 w68 h28 Default", "确认")

    BtnConfirm.OnEvent("Click", (*) => (MainGui.Opt("-Disabled"), ConfirmGui.Hide()))
    ConfirmGui.OnEvent("Close", (*) => (MainGui.Opt("-Disabled"), ConfirmGui.Hide()))

    MainGui.Opt("+Disabled")
    ConfirmGui.Show("w350 h150")

    OldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows true
    WinWaitClose(ConfirmGui)
    DetectHiddenWindows OldDetectState

    ConfirmGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
}

ShowMultiPathDialog(ValidGames) {
    global g_CurrentServer, MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    ChoiceGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    ChoiceGui.SetFont(, "Microsoft YaHei UI")

    ChoiceGui.Add("Text", "x20 y15 w410 h25", "选择 AION2 " . g_CurrentServer["name"] . "安装目录：")

    ListBoxItems := []
    for Game in ValidGames {
        ListBoxItems.Push("[" . Game.SoftwareDisplayName . "] -> " . Game.GameInstallPath)
    }

    ListControl := ChoiceGui.Add("ListBox", "x20 y45 w410 h130 r5 Choose1 +HScroll", ListBoxItems)

    BtnConfirm := ChoiceGui.Add("Button", "x262 y200 w84 h30 Default", "确认")
    BtnCancel := ChoiceGui.Add("Button", "x356 y200 w74 h30 ", "取消")

    UserChoicePath := ""
    BtnConfirm.OnEvent("Click", (*) => (UserChoicePath := ValidGames[ListControl.Value].GameInstallPath, MainGui.Opt(
        "-Disabled"), ChoiceGui.Hide()))
    BtnCancel.OnEvent("Click", (*) => (UserChoicePath := "", MainGui.Opt("-Disabled"), ChoiceGui.Hide()))
    ChoiceGui.OnEvent("Close", (*) => (UserChoicePath := "", MainGui.Opt("-Disabled"), ChoiceGui.Hide()))

    MainGui.Opt("+Disabled")
    ChoiceGui.Show("w450 h250")

    OldDetectState := A_DetectHiddenWindows
    DetectHiddenWindows true
    WinWaitClose(ChoiceGui)
    DetectHiddenWindows OldDetectState

    ChoiceGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
    return UserChoicePath
}

GetValidGamePaths() {
    global g_CurrentServer

    Keywords := (Type(g_CurrentServer) == "Map" && g_CurrentServer.Has("keywords")) ? g_CurrentServer["keywords"] : [
        "AION"]
    DetectedGames := FindGamesFromReg(Keywords)
    ValidGames := []

    for GameInfo in DetectedGames {
        if (FileExist(GameInfo.GameInstallPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            IsDuplicatePath := false
            for ExistingGame in ValidGames {
                if (PathUtil.Normalize(ExistingGame.GameInstallPath) == PathUtil.Normalize(GameInfo.GameInstallPath)) {
                    IsDuplicatePath := true
                    break
                }
            }
            if (!IsDuplicatePath) {
                ValidGames.Push(GameInfo)
            }
        }
    }
    return ValidGames
}

FindGamesFromReg(KeywordArray) {
    SystemUninstallRoot := "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    UserUninstallRoot := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    MatchedGameList := []

    SetRegView 64
    loop reg, SystemUninstallRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentDisplayName := RegRead(CurrentFullKey, "DisplayName", "")

        for Keyword in KeywordArray {
            IsDuplicatePath := false
            if (InStr(CurrentDisplayName, Keyword)) {
                CurrentInstallPath := RegRead(CurrentFullKey, "InstallLocation", "")
                if (CurrentInstallPath != "") {
                    for ExistingGame in MatchedGameList {
                        if (ExistingGame.GameInstallPath = CurrentInstallPath) {
                            IsDuplicatePath := true
                            break
                        }
                    }
                    if (!IsDuplicatePath) {
                        MatchedGameList.Push({
                            FullRegistryPath: CurrentFullKey,
                            RegistryKeyName: A_LoopRegName,
                            SoftwareDisplayName: CurrentDisplayName,
                            GameInstallPath: CurrentInstallPath
                        })
                    }
                }
            }
        }
    }

    SetRegView 32
    loop reg, SystemUninstallRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentDisplayName := RegRead(CurrentFullKey, "DisplayName", "")

        for Keyword in KeywordArray {
            IsDuplicatePath := false
            if (InStr(CurrentDisplayName, Keyword)) {
                CurrentInstallPath := RegRead(CurrentFullKey, "InstallLocation", "")
                if (CurrentInstallPath != "") {
                    for ExistingGame in MatchedGameList {
                        if (ExistingGame.GameInstallPath = CurrentInstallPath) {
                            IsDuplicatePath := true
                            break
                        }
                    }
                    if (!IsDuplicatePath) {
                        DisplayKeyString := StrReplace(CurrentFullKey, "SOFTWARE\", "SOFTWARE\WOW6432Node\")
                        MatchedGameList.Push({
                            FullRegistryPath: DisplayKeyString,
                            RegistryKeyName: A_LoopRegName,
                            SoftwareDisplayName: CurrentDisplayName,
                            GameInstallPath: CurrentInstallPath
                        })
                    }
                }
            }
        }
    }

    SetRegView "Default"
    loop reg, UserUninstallRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentDisplayName := RegRead(CurrentFullKey, "DisplayName", "")

        for Keyword in KeywordArray {
            IsDuplicatePath := false
            if (InStr(CurrentDisplayName, Keyword)) {
                CurrentInstallPath := RegRead(CurrentFullKey, "InstallLocation", "")
                if (CurrentInstallPath != "") {
                    for ExistingGame in MatchedGameList {
                        if (ExistingGame.GameInstallPath = CurrentInstallPath) {
                            IsDuplicatePath := true
                            break
                        }
                    }
                    if (!IsDuplicatePath) {
                        MatchedGameList.Push({
                            FullRegistryPath: CurrentFullKey,
                            RegistryKeyName: A_LoopRegName,
                            SoftwareDisplayName: CurrentDisplayName,
                            GameInstallPath: CurrentInstallPath
                        })
                    }
                }
            }
        }
    }

    return MatchedGameList
}

OnScanButtonClick() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath
    SectionName := "Server_" . g_CurrentServer["id"]

    ValidGames := GetValidGamePaths()

    if (ValidGames.Length = 1) {
        SelectedFolder := ValidGames[1].GameInstallPath
        ShowStatus("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
    } else if (ValidGames.Length > 1) {
        SelectedFolder := ShowMultiPathDialog(ValidGames)
        if (SelectedFolder = "")
            return
        ShowStatus("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
    } else {
        ShowMessageDialog("未检测到有效的安装目录，请通过[浏览...]按钮手动指定。")
        return
    }

    EditInstallPath.Value := SelectedFolder
    g_InstallPath := SelectedFolder
    g_ConfigCache.%SectionName%.InstallPath := SelectedFolder

    SaveAllConfig()
    RefreshUi()
}

SilentDetectFolder() {
    global g_ConfigCache, g_InstallPath, EditInstallPath
    SectionName := "Server_" . g_CurrentServer["id"]

    if (g_ConfigCache.%SectionName%.IsManualReset == 1)
        return

    ValidGames := GetValidGamePaths()

    if (ValidGames.Length = 1) {
        SelectedFolder := ValidGames[1].GameInstallPath
        EditInstallPath.Value := SelectedFolder
        g_InstallPath := SelectedFolder

        g_ConfigCache.%SectionName%.InstallPath := SelectedFolder
        SaveAllConfig()
        RefreshUi()
        ShowStatus("已自动识别并设置安装目录。")
    }
}

UpdateNoticeText() {
    global g_CurrentServer, TextExplain

    ServerName := (Type(g_CurrentServer) == "Map" && g_CurrentServer.Has("name")) ? g_CurrentServer["name"] : "台服"
    ServerId := (Type(g_CurrentServer) == "Map" && g_CurrentServer.Has("id")) ? g_CurrentServer["id"] : 102

    RuleText := "1. 选择 AION2 " . ServerName . "的安装目录，"
    RuleText .= (ServerId = 102) ? "例如 D:\Games\AION2_TW。" : "例如 D:\Games\AION 2。"

    TextExplain.Value := RuleText .
        "`r`n2. 汉化完成后启动或重启 AION2，使汉化文件生效。" .
        "`r`n3. 如发生异常问题，使用“撤销汉化”功能，或在 PURPLE 或 Steam 进行修复，" .
        "`r`n   PURPLE : AION2 - 游戏设置 - 检查文件；" .
        "`r`n   Steam : AION2 -  属性 - 已安装的文件 - 验证游戏文件的完整性；" .
        "`r`n4. 汉化文件来自网游加速器，本工具为第三方扩展，使用即代表您知悉并自愿承担所有风险。"
}

HashFileMd5(FilePath) {
    try {
        RunWait(A_ComSpec . ' /c certutil -hashfile "' . FilePath .
            '" MD5 | findstr /v ":" | findstr /v "CertUtil" > "' . A_Temp . '\md5.txt"', , "Hide")
        if FileExist(A_Temp . '\md5.txt') {
            Res := FileRead(A_Temp . '\md5.txt')
            FileDelete(A_Temp . '\md5.txt')
            return StrLower(StrReplace(StrReplace(Trim(Res), "`r"), "`n"))
        }
    }
    return ""
}

WriteFileAtomic(FilePath, TextContent) {
    TmpFile := FilePath . ".tmp"

    try {
        if FileExist(TmpFile)
            FileDelete(TmpFile)

        FileObj := FileOpen(TmpFile, "w", "UTF-8")
        FileObj.Write(TextContent)
        FileObj.Close()

        if FileExist(FilePath)
            FileDelete(FilePath)

        FileMove(TmpFile, FilePath, 1)
        return true
    } catch {
        if FileExist(TmpFile)
            FileDelete(TmpFile)
        return false
    }
}

ShowStatus(StatusMessage) {
    global MainStatusBar
    MainStatusBar.SetText("`t" . StatusMessage)
    SetTimer(() => MainStatusBar.SetText(""), -3000)
}
