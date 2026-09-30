#Requires AutoHotkey v2.0
;@Ahk2Exe-SetName AION2 Chs Patch
;@Ahk2Exe-SetOrigFilename AION2_Chs_P.exe
;@Ahk2Exe-SetProductName AION2 Chs Patch
;@Ahk2Exe-SetDescription AION2 一键汉化工具
;@Ahk2Exe-SetVersion 1.8.0.0
;@Ahk2Exe-SetCopyright Copyright © 2026
;@Ahk2Exe-SetMainIcon AutoHotkey\icon.ico
#Include ".\AutoHotkey\lib\UniqueInstance.ahk"
#Include ".\AutoHotkey\lib\PathUtil.ahk"
#Include ".\AutoHotkey\Lib\WinHttpRequest.ahk"
#Include ".\AutoHotkey\lib\DownloadAsync.ahk"
#Include ".\AutoHotkey\lib\JSON.ahk"
;@format array_style: expand, object_style: expand

Persistent true
#SingleInstance Off

; ==============================================================================
; 单实例与权限保障
; ==============================================================================

UniqueInstance.Ensure(Map(
    "preferRunAsAdmin", true,
    "allowCoexist", true,
    "showReport", true
))

; ==============================================================================
; 全局常量与变量定义
; ==============================================================================

global g_ProjectName := "AION2 Chs Patch"
global g_CurrentAppVersion := "1.8.0.0"
global g_CurrentAppVersionShort := "1.8"
global g_LastSeenBulletinVersion := "1.0.0.0"

global g_ConfigFile := "config.ini"
global g_AppManifestFilename := "app_manifest.json"
global g_PatchManifestFilename := "patch_manifest.json"
global g_PatchesCacheDir := "patches"

global g_DefaultPreUrl := "https://raw.githubusercontent.com/nanhezzb/Aion2-Chinese-Patch/main"
global g_DefaultProxyMirrors := [
    "https://gh-proxy.com",
    "https://gh.ddlc.top",
    "https://ghproxy.net",
    "https://github.dpik.top"
]
global g_DefaultGameProcesses := []
global g_DefaultServers := []

global g_GlobalConfigData := Map()
global g_ClientUpdateData := Map()
global g_ServersConfigData := []
global g_CloudBulletinData := Map()

global g_IsLocalInitComplete := false
global g_InstallPath := ""
global g_RequestTimeoutSeconds := 30
global g_CleanPreUrl := RTrim(g_DefaultPreUrl, "/")
global g_CleanProxyMirrors := []
global g_BestDownloadPrefix := ""
global g_BestLatency := 99999
global g_CurrentServer := Map()
global g_ConfigCache := {
    Settings: {
        LastServerID: 102
    }
}
global g_DialogCallbacks := Map()
global g_IsPatching := false
global g_IsSyncing := false
global g_WindowsOffset := 0

; 统一响应句柄映射
global g_CursorHwndMap := Map()

; Win32 API 控制常量
global LVM_FIRST := 0x1000
global LVM_GETHEADER := LVM_FIRST + 31
global LVM_SETEXTENDEDLISTVIEWSTYLE := LVM_FIRST + 54
global LVM_GETEXTENDEDLISTVIEWSTYLE := LVM_FIRST + 55

global LVS_EX_HEADERDRAGDROP := 0x00000010
global LVS_EX_FULLROWSELECT := 0x00000020
global LVS_EX_INFOTIP := 0x00000400
global LVS_EX_LABELTIP := 0x00004000
global LVS_EX_DOUBLEBUFFER := 0x00010000

global HDM_FIRST := 0x1200
global HDM_GETITEM := HDM_FIRST + 11
global HDM_SETITEM := HDM_FIRST + 12

global HDI_FORMAT := 0x0004
global HDF_SORTDOWN := 0x0200
global HDF_SORTUP := 0x0400

; ==============================================================================
; 主界面 GUI 构建
; ==============================================================================

global MainGui := Gui(, "AION2 一键汉化工具 " . g_CurrentAppVersionShort)
MainGui.SetFont("s9", "Microsoft YaHei")

global TabCtrl := MainGui.Add("Tab3", "x-1 y10 w574 h460", [
    "一键汉化",
    "免费加速器"
])

TabCtrl.UseTab(1)
MainGui.Add("GroupBox", "x17 y45 w536 h75", " 选择服务器 * ")
global ComboServerList := MainGui.Add("DropDownList", "x27 y75 w516 Choose1", [])

MainGui.Add("GroupBox", "x17 y130 w536 h115", " 选择安装目录 * ")
global EditInstallPath := MainGui.Add("Edit", "x27 y160 w516 r1 ReadOnly", "")
global BtnScan := MainGui.Add("Button", "x340 y201 w60 h26", "查找")
global BtnBrowse := MainGui.Add("Button", "x412 y201 w60 h26", "浏览…")
global BtnReset := MainGui.Add("Button", "x484 y201 w60 h26 +Disabled", "重置")

MainGui.Add("GroupBox", "x17 y255 w536 h145", "使用须知 * ")
global TextExplain := MainGui.AddText("x31 y280 w510 h105", "")

global TextTipInfo := MainGui.Add("Text", "x0 y405 w575 +Hidden cRed Center", "建议先退出游戏再进行汉化。")
global BtnUpdate := MainGui.Add("Button", "x177 y418 w100 h30 +Hidden", "更新补丁")
global BtnChinese := MainGui.Add("Button", "x177 y418 w100 h30", "一键汉化")
global BtnRestore := MainGui.Add("Button", "x289 y418 w100 h30", "撤销汉化")
global BtnRefreshStatus := MainGui.Add("Button", "x484 y422 w60 h26", "刷新")
AddToolTip(BtnRefreshStatus, "检测本地补丁是否失效，刷新界面按钮状态。")

TabCtrl.UseTab(2)

CreateCardControl(MainGui, {
    x: 12,
    y: 45,
    icon: ".\AutoHotkey\XaoYao.png",
    title: "逍遥加速器",
    desc: "24 小时免费加速，支持 Steam、PURPLE、EA、Epic、暴雪等游戏平台，使用“平台加速”功能，加速平台内全部游戏（含塔2 国际服）。",
    url: "https://www.xiaoyao.co/index.htm",
    width: 536,
    height: 79,
    border: true
})

CreateCardControl(MainGui, {
    x: 12,
    y: 129,
    icon: ".\AutoHotkey\GuGuai.png",
    title: "古怪加速器",
    desc: "Bilibili 搜索口令获取永久时长， 0 - 16 时免费加速，极速稳定支持全球网游。",
    url: "https://www.ggkuai.com/",
    width: 536,
    height: 77,
    border: true
})

CreateCardControl(MainGui, {
    x: 12,
    y: 211,
    icon: ".\AutoHotkey\AK.png",
    title: "AK加速器",
    desc: "0 - 14 时免费加速，支持全球网游加速。",
    url: "https://www.akspeedy.com/html/invite_new/invite_download.html?inviter=3Xtkus4t",
    width: 536,
    height: 77,
    border: true
})

TabCtrl.UseTab(0)

global MainStatusBar := MainGui.Add("StatusBar", "")

; ==============================================================================
; 统一注册监听
; ==============================================================================

TabCtrl.OnEvent("Change", (*) => RefreshUi())
MainGui.OnEvent("Close", (*) => MainGui.Hide())

ComboServerList.OnEvent("Change", (*) => SelectServer())
BtnScan.OnEvent("Click", (*) => OnScanButtonClick())
BtnBrowse.OnEvent("Click", BrowseFolder)
BtnReset.OnEvent("Click", DoResetConfig)
BtnUpdate.OnEvent("Click", DoUpdatePatch)
BtnChinese.OnEvent("Click", DoChinesePatch)
BtnRestore.OnEvent("Click", DoRestorePatch)
BtnRefreshStatus.OnEvent("Click", OnBtnRefreshStatusClick)

; 设置系统托盘图标
#NoTrayIcon
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("显示主界面", (*) => MainGui.Show())
Tray.Add("退出程序", (*) => ExitApp())
Tray.Default := "显示主界面"
Tray.ClickCount := 1
TraySetIcon("AutoHotkey\icon.ico", , 1)
A_IconHidden := false

OnMessage(0x404, MyTrayClick)

MyTrayClick(wParam, lParam, msg, hwnd) {
    if (lParam == 0x0203) {
        MainGui.Show()
    }
}

; ==============================================================================
; 冷启动时缺省配置
; ==============================================================================

g_DefaultServers := NormalizeServerConfig([
    Map(
        "id", 102,
        "name", "台服",
        "display", "台服 - PURPLE",
        "keywords", [
            "AION"
        ],
        "patch_branches", [
            Map("id", 3,
                "source", "BiuBiu",
                "latest_patch_version", "1.0.0.0",
                "actions", [
                    Map(
                        "type", "add",
                        "filename", "bb_pakchunk999999-Windows_0_P.Pak",
                        "remote_filename", "patchs/bb_pakchunk999999-Windows_0_P.Pak",
                        "target_relative_path", "Aion2\\Content\\Paks\\bb_pakchunk999999-Windows_0_P.Pak",
                        "file_md5", "12a93a1ecba45ad9803ae2c20495781d",
                        "file_size", 3721650
                    )
                ]
            )
        ]
    )
])

g_ServersConfigData := g_DefaultServers
InitProxyMirrors(g_DefaultProxyMirrors)
InitializeApp()

; ==============================================================================
; 1. 初始化与应用生命周期模块
; ==============================================================================

InitializeApp() {
    global g_IsLocalInitComplete, g_IsSyncing, MainGui, g_WindowsOffset

    g_IsSyncing := true
    MainGui.Show("w570 h490")

    g_WindowsOffset := GetWindowFrameOffset(MainGui)

    RefreshUi()
    SetStatusBarText("正在初始化环境…")

    LoadLocalManifests()
    ReadConfig()

    g_IsLocalInitComplete := true
    SetStatusBarText("本地数据就绪。")

    SetTimer(StartCloudSync, -300)
}

ParseAndApplyManifest(JsonContent, IsPatchFile := false) {
    global g_ClientUpdateData, g_ServersConfigData, g_CloudBulletinData, g_GlobalConfigData, g_DefaultProxyMirrors, g_DefaultGameProcesses

    if (JsonContent == "")
        return false

    try {
        Parsed := JSON.parse(JsonContent)
        if (Type(Parsed) != "Map")
            return false

        if (Parsed.Has("client_update") && Type(Parsed["client_update"]) == "Map")
            g_ClientUpdateData := Parsed["client_update"]

        if (IsPatchFile && Parsed.Has("servers_config") && Type(Parsed["servers_config"]) == "Array")
            g_ServersConfigData := NormalizeServerConfig(Parsed["servers_config"])

        if (IsPatchFile && Parsed.Has("cloud_bulletin") && Type(Parsed["cloud_bulletin"]) == "Map")
            g_CloudBulletinData := Parsed["cloud_bulletin"]

        if (Parsed.Has("global_config") && Type(Parsed["global_config"]) == "Map") {
            g_GlobalConfigData := Parsed["global_config"]
            InitProxyMirrors(SafeGet(g_GlobalConfigData, "proxy_mirrors", g_DefaultProxyMirrors))

            if (!g_GlobalConfigData.Has("game_processes") || Type(g_GlobalConfigData["game_processes"]) != "Array") {
                g_GlobalConfigData["game_processes"] := g_DefaultGameProcesses
            }
        }
        return true
    } catch {
        return false
    }
}

LoadLocalManifests() {
    global g_AppManifestFilename, g_PatchManifestFilename, g_ServersConfigData, g_DefaultServers

    if FileExist(g_AppManifestFilename) {
        try ParseAndApplyManifest(FileRead(g_AppManifestFilename, "UTF-8"), false)
    }

    if FileExist(g_PatchManifestFilename) {
        try {
            if (!ParseAndApplyManifest(FileRead(g_PatchManifestFilename, "UTF-8"), true))
                g_ServersConfigData := g_DefaultServers
        } catch {
            g_ServersConfigData := g_DefaultServers
        }
    } else {
        g_ServersConfigData := g_DefaultServers
    }
}

StartCloudSync() {
    global g_ConfigFile, g_RequestTimeoutSeconds, g_IsLocalInitComplete, g_IsSyncing, g_CleanPreUrl, g_AppManifestFilename, g_PatchManifestFilename, MainStatusBar

    if (!g_IsLocalInitComplete)
        return

    g_IsSyncing := true
    RefreshUi()

    try {
        MainStatusBar.SetText("`t正在获取服务器配置文件…")

        BestPrefix := ""
        try BestPrefix := SelectFastestMirrorNode()

        Timestamp := "?t=" . DateDiff(A_NowUTC, "19700101000000", "Seconds")
        AppRelPath := g_CleanPreUrl . "/" . g_AppManifestFilename . Timestamp
        PatchRelPath := g_CleanPreUrl . "/" . g_PatchManifestFilename . Timestamp

        AppUrl := (BestPrefix != "") ? BestPrefix . "/" . AppRelPath : AppRelPath
        PatchUrl := (BestPrefix != "") ? BestPrefix . "/" . PatchRelPath : PatchRelPath

        IsAppSuccess := false
        IsPatchSuccess := false

        if (AppJson := HttpGetText(AppUrl, g_RequestTimeoutSeconds)) {
            if (ParseAndApplyManifest(AppJson, false)) {
                WriteFileAtomic(g_AppManifestFilename, AppJson)
                IsAppSuccess := true
            }
        }

        if (PatchJson := HttpGetText(PatchUrl, g_RequestTimeoutSeconds)) {
            if (ParseAndApplyManifest(PatchJson, true)) {
                WriteFileAtomic(g_PatchManifestFilename, PatchJson)
                IsPatchSuccess := true
            }
        }

        if (IsAppSuccess && IsPatchSuccess) {
            SafeIniWrite(DateDiff(A_NowUTC, "19700101000000", "Seconds"), g_ConfigFile, "Settings", "LastCheckTime")
            SafeIniWrite(g_RequestTimeoutSeconds, g_ConfigFile, "Settings", "RequestTimeoutSeconds")

            RefreshServerComboBox()
            SetStatusBarText("云端配置同步成功，已更新至最新数据。")
        } else {
            SetStatusBarText("连接超时或离线，已加载本地配置文件。")
        }

        ExecuteCheckChain()

    } finally {
        g_IsSyncing := false
        RefreshUi()
    }
}

ExecuteCheckChain() {
    global g_ClientUpdateData, g_CloudBulletinData, g_CurrentServer

    CheckTasks := []

    if (Type(g_ClientUpdateData) == "Map" && g_ClientUpdateData.Count > 0) {
        CheckTasks.Push((OnNext) => CheckClientUpdate(g_ClientUpdateData, OnNext))
    }

    if (Type(g_CloudBulletinData) == "Map" && g_CloudBulletinData.Count > 0) {
        CheckTasks.Push((OnNext) => CheckBulletin(g_CloudBulletinData, OnNext))
    }

    if (Type(g_CurrentServer) == "Map" && g_CurrentServer.Has("patch_branches")) {
        CheckTasks.Push((OnNext) => CheckPatchUpdate(g_CurrentServer, OnNext))
    }

    TaskIndex := 1
    NextTask() {
        if (TaskIndex <= CheckTasks.Length) {
            CurrentTask := CheckTasks[TaskIndex]
            TaskIndex++
            CurrentTask(NextTask)
        }
    }

    NextTask()
}

; ==============================================================================
; 2. 配置与缓存管理模块
; ==============================================================================

InitProxyMirrors(MirrorsArray) {
    global g_CleanProxyMirrors := []
    if (Type(MirrorsArray) == "Array") {
        for Mirror in MirrorsArray {
            StrMirror := SafeString(Mirror)
            if (StrMirror != "")
                g_CleanProxyMirrors.Push(RTrim(StrMirror, "/"))
        }
    }
}

ReadConfig() {
    global g_ConfigCache, g_ConfigFile, g_ServersConfigData, g_LastSeenBulletinVersion
    g_LastSeenBulletinVersion := SafeIniRead(g_ConfigFile, "Settings", "LastSeenBulletinVersion", "1.0.0.0")

    g_ConfigCache := {
        Settings: {
            LastServerID: SafeNumber(SafeIniRead(g_ConfigFile, "Settings", "LastServerID", 102), 102)
        }
    }

    IniSections := SafeIniReadSections(g_ConfigFile)
    if (IniSections != "") {
        loop parse, IniSections, "`n", "`r" {
            SecName := Trim(A_LoopField)
            if (SubStr(SecName, 1, 8) == "Profile_") {
                S_ID := SafeNumber(SafeIniRead(g_ConfigFile, SecName, "server_id", 0), 0)
                B_ID := SafeNumber(SafeIniRead(g_ConfigFile, SecName, "branch_id", 0), 0)
                I_Path := SafeIniRead(g_ConfigFile, SecName, "install_path", "")

                if (S_ID > 0 && I_Path != "") {
                    NormalizedIPath := PathUtil.Normalize(I_Path)
                    StandardKey := GetProfileKey(S_ID, NormalizedIPath, B_ID)

                    g_ConfigCache.%StandardKey% := {
                        ServerID: S_ID,
                        BranchID: B_ID,
                        InstallPath: NormalizedIPath,
                        IsPatched: SafeNumber(SafeIniRead(g_ConfigFile, SecName, "is_patched", 0), 0),
                        LocalPatchVersion: SafeIniRead(g_ConfigFile, SecName, "local_patch_version", ""),
                        LocalPatchBranchID: SafeNumber(SafeIniRead(g_ConfigFile, SecName, "local_patch_branch_id", B_ID), B_ID)
                    }
                }
            }
        }
    }

    for Server in g_ServersConfigData {
        Sec := "Server_" . Server["id"]
        RawSavedPath := SafeIniRead(g_ConfigFile, Sec, "install_path", "")
        SavedInstallPath := (RawSavedPath != "") ? PathUtil.Normalize(RawSavedPath) : ""

        if (SavedInstallPath == "") {
            for KeyName, ConfigObj in g_ConfigCache.OwnProps() {
                if (SubStr(KeyName, 1, 8) == "Profile_" && Type(ConfigObj) == "Object" && ConfigObj.HasOwnProp("ServerID") && ConfigObj.ServerID == Server["id"]) {
                    if (ConfigObj.HasOwnProp("InstallPath") && ConfigObj.InstallPath != "" && DirExist(ConfigObj.InstallPath)) {
                        SavedInstallPath := ConfigObj.InstallPath
                        break
                    }
                }
            }
        }

        g_ConfigCache.%Sec% := {
            InstallPath: SavedInstallPath,
            IsManualReset: SafeNumber(SafeIniRead(g_ConfigFile, Sec, "is_manual_reset", 0), 0)
        }
    }

    RefreshServerComboBox()
}

SaveAllConfig() {
    global g_ConfigCache, g_ConfigFile, g_ServersConfigData, g_LastSeenBulletinVersion

    if (g_ConfigCache.HasOwnProp("Settings") && g_ConfigCache.Settings.HasOwnProp("LastServerID")) {
        SafeIniWrite(g_ConfigCache.Settings.LastServerID, g_ConfigFile, "Settings", "LastServerID")
    }
    SafeIniWrite(g_LastSeenBulletinVersion, g_ConfigFile, "Settings", "LastSeenBulletinVersion")

    for Server in g_ServersConfigData {
        Sec := "Server_" . Server["id"]
        if (g_ConfigCache.HasOwnProp(Sec)) {
            SafeIniWrite(g_ConfigCache.%Sec%.InstallPath, g_ConfigFile, Sec, "install_path")
            SafeIniWrite(g_ConfigCache.%Sec%.IsManualReset, g_ConfigFile, Sec, "is_manual_reset")
        }
    }

    ExistingSections := SafeIniReadSections(g_ConfigFile)
    if (ExistingSections != "") {
        loop parse, ExistingSections, "`n", "`r" {
            SecName := Trim(A_LoopField)
            if (SubStr(SecName, 1, 8) == "Profile_") {
                try IniDelete(g_ConfigFile, SecName)
            }
        }
    }

    WrittenProfiles := Map()

    for KeyName, ConfigObj in g_ConfigCache.OwnProps() {
        if (SubStr(KeyName, 1, 8) == "Profile_" && Type(ConfigObj) == "Object") {
            ServerID := ConfigObj.HasOwnProp("ServerID") ? ConfigObj.ServerID : 0
            BranchID := ConfigObj.HasOwnProp("BranchID") ? ConfigObj.BranchID : 1
            InstallPath := ConfigObj.HasOwnProp("InstallPath") ? ConfigObj.InstallPath : ""

            if (ServerID == 0 || InstallPath == "")
                continue

            UniqueSignature := ServerID . "|" . BranchID . "|" . StrLower(PathUtil.Normalize(InstallPath))
            if (WrittenProfiles.Has(UniqueSignature))
                continue

            WrittenProfiles[UniqueSignature] := true
            StandardSectionName := GetProfileKey(ServerID, InstallPath, BranchID)

            SafeIniWrite(ServerID, g_ConfigFile, StandardSectionName, "server_id")
            SafeIniWrite(BranchID, g_ConfigFile, StandardSectionName, "branch_id")
            SafeIniWrite(PathUtil.Normalize(InstallPath), g_ConfigFile, StandardSectionName, "install_path")

            if ConfigObj.HasOwnProp("IsPatched")
                SafeIniWrite(ConfigObj.IsPatched, g_ConfigFile, StandardSectionName, "is_patched")
            if ConfigObj.HasOwnProp("LocalPatchVersion")
                SafeIniWrite(ConfigObj.LocalPatchVersion, g_ConfigFile, StandardSectionName, "local_patch_version")
            if ConfigObj.HasOwnProp("LocalPatchBranchID")
                SafeIniWrite(ConfigObj.LocalPatchBranchID, g_ConfigFile, StandardSectionName, "local_patch_branch_id")
        }
    }
}

GetProfileKey(ServerID, InstallPath, BranchID := 1) {
    if (InstallPath == "")
        return ""

    NormalizedPath := StrLower(PathUtil.Normalize(InstallPath))
    RawString := ServerID . "|" . NormalizedPath . "|" . BranchID
    PathHash := SubStr(HashStringMd5(RawString), 1, 8)

    return "Profile_" . ServerID . "_" . BranchID . "_" . PathHash
}

GetBackupRootDir(ServerID, InstallPath, BranchID := 1) {
    ProfileKey := GetProfileKey(ServerID, InstallPath, BranchID)
    return PathUtil.Normalize(A_ScriptDir . "\rawBackup\" . ProfileKey)
}

GetSavedBranchID() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath
    ServerId := g_CurrentServer.Has("id") ? g_CurrentServer["id"] : "default"

    if (g_InstallPath != "") {
        NormalizedCurrentPath := StrLower(PathUtil.Normalize(g_InstallPath))

        for KeyName, ConfigObj in g_ConfigCache.OwnProps() {
            if (SubStr(KeyName, 1, 8) == "Profile_" && Type(ConfigObj) == "Object") {
                if (ConfigObj.HasOwnProp("ServerID") && ConfigObj.ServerID == ServerId) {
                    if (ConfigObj.HasOwnProp("InstallPath") && ConfigObj.InstallPath != "" && StrLower(PathUtil.Normalize(ConfigObj.InstallPath)) == NormalizedCurrentPath) {
                        if (ConfigObj.HasOwnProp("LocalPatchBranchID") && ConfigObj.LocalPatchBranchID > 0)
                            return ConfigObj.LocalPatchBranchID
                    }
                }
            }
        }

        BackupBaseDir := PathUtil.Normalize(A_ScriptDir . "\rawBackup")
        if DirExist(BackupBaseDir) {
            loop files, BackupBaseDir . "\*", "D" {
                ManifestPath := A_LoopFileFullPath . "\backup_manifest.json"
                if FileExist(ManifestPath) {
                    try {
                        Parsed := JSON.parse(FileRead(ManifestPath, "UTF-8"))
                        if (Type(Parsed) == "Map" && Parsed.Has("install_path") && Parsed.Has("branch_id")) {
                            if (StrLower(PathUtil.Normalize(Parsed["install_path"])) == NormalizedCurrentPath)
                                return SafeNumber(Parsed["branch_id"], 1)
                        }
                    }
                }
            }
        }
    }

    Sec := "Server_" . ServerId
    return (g_ConfigCache.HasOwnProp(Sec) && Type(g_ConfigCache.%Sec%) == "Object" && g_ConfigCache.%Sec%.HasOwnProp("LocalPatchBranchID")) ? SafeNumber(g_ConfigCache.%Sec%.LocalPatchBranchID, 1) : 1
}

; ==============================================================================
; 3. 服务器、游戏路径扫描与管理模块
; ==============================================================================

RefreshServerComboBox() {
    global g_ServersConfigData, ComboServerList, g_ConfigFile, g_CurrentServer, g_ConfigCache

    DropDownOptions := []
    SavedLastId := SafeNumber(SafeIniRead(g_ConfigFile, "Settings", "LastServerID", 102), 102)
    TargetIndex := 1

    if (g_ServersConfigData.Length == 0) {
        ComboServerList.Delete()
        ComboServerList.Add([])
        g_CurrentServer := Map()
        return
    }

    loop g_ServersConfigData.Length {
        Server := g_ServersConfigData[A_Index]
        DropDownOptions.Push(Server["display"])
        if (Server["id"] == SavedLastId)
            TargetIndex := A_Index
    }

    ComboServerList.Delete()
    ComboServerList.Add(DropDownOptions)
    ComboServerList.Value := TargetIndex

    if (TargetIndex <= g_ServersConfigData.Length) {
        g_CurrentServer := g_ServersConfigData[TargetIndex]
        if (!g_ConfigCache.HasOwnProp("Settings"))
            g_ConfigCache.Settings := {}
        g_ConfigCache.Settings.LastServerID := g_CurrentServer["id"]
    }

    RefreshServerData()
    if (g_InstallPath == "")
        AutoDetectInstallPath()
}

RefreshServerData() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath

    if (!g_CurrentServer.Has("id"))
        return

    Sec := "Server_" . g_CurrentServer["id"]
    UpdateServerNoticeText()

    if (!g_ConfigCache.HasOwnProp(Sec)) {
        g_ConfigCache.%Sec% := {
            InstallPath: "",
            IsManualReset: 0
        }
    }

    SavedPath := g_ConfigCache.%Sec%.InstallPath
    if (SavedPath != "") {
        NormalizedSavedPath := PathUtil.Normalize(SavedPath)
        if (DirExist(NormalizedSavedPath) && FileExist(NormalizedSavedPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            g_InstallPath := NormalizedSavedPath
            EditInstallPath.Value := NormalizedSavedPath
        } else {
            g_InstallPath := ""
            EditInstallPath.Value := ""
            g_ConfigCache.%Sec%.InstallPath := ""
            SaveAllConfig()
            ShowMessageDialog("无效的目录地址，安装目录已重置。")
        }
    } else {
        g_InstallPath := ""
        EditInstallPath.Value := ""
    }
    RefreshUi()
}

SelectServer() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, ComboServerList, g_ServersConfigData

    if (ComboServerList.Value <= 0 || ComboServerList.Value > g_ServersConfigData.Length)
        return

    g_CurrentServer := g_ServersConfigData[ComboServerList.Value]

    if (!g_ConfigCache.HasOwnProp("Settings"))
        g_ConfigCache.Settings := {}
    g_ConfigCache.Settings.LastServerID := g_CurrentServer["id"]
    SaveAllConfig()

    RefreshServerData()
    SetStatusBarText("已切换至 " . g_CurrentServer["name"] . " 配置。")

    if (g_InstallPath == "")
        AutoDetectInstallPath()
}

SetInstallPath(NewPath, IsManualReset := 0) {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath, BtnChinese
    Sec := "Server_" . g_CurrentServer["id"]
    NewPathNormalized := (NewPath != "") ? PathUtil.Normalize(NewPath) : ""

    g_InstallPath := NewPathNormalized
    EditInstallPath.Value := NewPathNormalized

    if (!g_ConfigCache.HasOwnProp(Sec))
        g_ConfigCache.%Sec% := {}

    g_ConfigCache.%Sec%.InstallPath := NewPathNormalized
    g_ConfigCache.%Sec%.IsManualReset := IsManualReset

    SaveAllConfig()
    RefreshUi()
}

AutoDetectInstallPath() {
    global g_ConfigCache, g_CurrentServer
    SectionName := "Server_" . g_CurrentServer["id"]

    if (g_ConfigCache.HasOwnProp(SectionName) && Type(g_ConfigCache.%SectionName%) == "Object" && g_ConfigCache.%SectionName%.HasOwnProp("IsManualReset") && g_ConfigCache.%SectionName%.IsManualReset == 1)
        return

    ValidGames := GetValidGamePaths()

    if (ValidGames.Length == 1) {
        SelectedFolder := ValidGames[1].GameInstallPath
        SetInstallPath(SelectedFolder, 0)
        SetStatusBarText("已自动识别并设置安装目录。")
    }
}

OnScanButtonClick() {
    global g_CurrentServer

    ValidGames := GetValidGamePaths()

    if (ValidGames.Length == 1) {
        SelectedFolder := ValidGames[1].GameInstallPath
        SetInstallPath(SelectedFolder, 0)
        SetStatusBarText("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
    } else if (ValidGames.Length > 1) {
        ShowMultiPathDialog(ValidGames, HandleScanPathSelected)
    } else {
        ShowMessageDialog("未检测到有效的安装目录，通过[浏览…]按钮手动指定。")
    }
}

HandleScanPathSelected(SelectedFolder) {
    global g_CurrentServer
    if (SelectedFolder != "") {
        SetInstallPath(SelectedFolder, 0)
        SetStatusBarText("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
    }
}

DoResetConfig(*) {
    global g_CurrentServer
    SetInstallPath("", 1)
    SetStatusBarText("AION2 " . g_CurrentServer["name"] . "安装目录已重置。")
}

BrowseFolder(*) {
    global g_CurrentServer, EditInstallPath
    SelectedFolder := FileSelect("D", EditInstallPath.Value, "选择 AION2 " . g_CurrentServer["name"] . "安装目录：")
    if (SelectedFolder == "")
        return

    NormalizedSelectedFolder := PathUtil.Normalize(SelectedFolder)
    if (!FileExist(NormalizedSelectedFolder . "\Aion2\Binaries\Win64\Aion2.exe")) {
        ShowMessageDialog("所选目录中未检测主程序 Aion2.exe，重新选择正确的安装目录。")
        return
    }
    SetInstallPath(NormalizedSelectedFolder, 0)
    SetStatusBarText("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
}

UpdateServerNoticeText() {
    global g_CurrentServer, TextExplain
    ServerName := g_CurrentServer["name"]
    RuleText := "1. 选择 AION2 " . ServerName . "的安装目录，" . ((g_CurrentServer["id"] == 102) ? "例如 D:\Games\AION2_TW。" : "例如 D:\Games\AION2。")
    TextExplain.Value := RuleText .
        "`r`n2. 汉化完成后启动或重启 AION2，使汉化文件生效。" .
        "`r`n3. 如发生异常问题，使用“撤销汉化”功能，或在 PURPLE / Steam 修复文件；" .
        "`r`n   PURPLE : AION2 - 游戏设置 - 检查文件；" .
        "`r`n   Steam : AION2 - 属性 - 已安装的文件 - 验证游戏文件的完整性；" .
        "`r`n4. 本工具为第三方扩展，使用即代表您自愿承担所有风险。"
}

GetValidGamePaths() {
    global g_CurrentServer

    Keywords := (Type(g_CurrentServer) == "Map" && g_CurrentServer.Has("keywords")) ? g_CurrentServer["keywords"] : [
        "AION"
    ]

    RawDetectedGames := []
    RawDetectedGames.Push(ScanGamesFromUninstallReg(Keywords)*)
    RawDetectedGames.Push(ScanGamesFromPlayNcReg()*)
    RawDetectedGames.Push(ScanGamesFromSteam()*)

    ValidGames := []

    for GameInfo in RawDetectedGames {
        NormalizedInstallPath := PathUtil.Normalize(GameInfo.GameInstallPath)

        if (FileExist(NormalizedInstallPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            IsDuplicatePath := false

            for ExistingGame in ValidGames {
                if (StrLower(ExistingGame.GameInstallPath) == StrLower(NormalizedInstallPath)) {
                    IsDuplicatePath := true
                    break
                }
            }

            if (!IsDuplicatePath) {
                GameInfo.GameInstallPath := NormalizedInstallPath
                ValidGames.Push(GameInfo)
            }
        }
    }
    return ValidGames
}

SafeRegRead(KeyPath, ValueName := "") {
    try return RegRead(KeyPath, ValueName)
    catch
        return ""
}

IsKeywordMatch(DisplayName, Keywords) {
    if (Type(Keywords) != "Array" || Keywords.Length == 0)
        return true
    for Keyword in Keywords {
        StrKw := SafeString(Keyword)
        if (StrKw != "" && InStr(DisplayName, StrKw))
            return true
    }
    return false
}

ScanGamesFromUninstallReg(KeywordArray := []) {
    SystemUninstallRoot := "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    UserUninstallRoot := "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    MatchedGameList := []

    TryAddUninstallEntry(FullKey, RegName, DisplayName, RawInstallPath) {
        if (RawInstallPath == "")
            return
        CleanPath := PathUtil.Normalize(RawInstallPath)
        CleanPathLower := StrLower(CleanPath)

        for ExistingGame in MatchedGameList {
            if (StrLower(ExistingGame.GameInstallPath) == CleanPathLower)
                return
        }

        MatchedGameList.Push({
            FullRegistryPath: FullKey,
            RegistryKeyName: RegName,
            SoftwareDisplayName: DisplayName,
            GameInstallPath: CleanPath,
            ScanMethod: "uninstall"
        })
    }

    SetRegView 64
    loop reg, SystemUninstallRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentDisplayName := SafeRegRead(CurrentFullKey, "DisplayName")

        if (CurrentDisplayName != "" && IsKeywordMatch(CurrentDisplayName, KeywordArray)) {
            CurrentInstallPath := SafeRegRead(CurrentFullKey, "InstallLocation")
            TryAddUninstallEntry(CurrentFullKey, A_LoopRegName, CurrentDisplayName, CurrentInstallPath)
        }
    }

    SetRegView 32
    loop reg, SystemUninstallRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentDisplayName := SafeRegRead(CurrentFullKey, "DisplayName")

        if (CurrentDisplayName != "" && IsKeywordMatch(CurrentDisplayName, KeywordArray)) {
            CurrentInstallPath := SafeRegRead(CurrentFullKey, "InstallLocation")
            DisplayKeyString := RegExReplace(CurrentFullKey, "i)^HKEY_LOCAL_MACHINE\\SOFTWARE\\", "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\")
            TryAddUninstallEntry(DisplayKeyString, A_LoopRegName, CurrentDisplayName, CurrentInstallPath)
        }
    }

    SetRegView "Default"
    loop reg, UserUninstallRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentDisplayName := SafeRegRead(CurrentFullKey, "DisplayName")

        if (CurrentDisplayName != "" && IsKeywordMatch(CurrentDisplayName, KeywordArray)) {
            CurrentInstallPath := SafeRegRead(CurrentFullKey, "InstallLocation")
            TryAddUninstallEntry(CurrentFullKey, A_LoopRegName, CurrentDisplayName, CurrentInstallPath)
        }
    }

    return MatchedGameList
}

ScanGamesFromPlayNcReg() {
    SystemPlayNcRoot := "HKEY_LOCAL_MACHINE\SOFTWARE\plaync"
    UserPlayNcRoot := "HKEY_CURRENT_USER\SOFTWARE\plaync"
    MatchedGameList := []

    TryAddPlayNcEntry(FullKey, RegName, RawInstallPath) {
        if (RawInstallPath == "")
            return
        CleanPath := PathUtil.Normalize(RawInstallPath)
        CleanPathLower := StrLower(CleanPath)

        for ExistingGame in MatchedGameList {
            if (StrLower(ExistingGame.GameInstallPath) == CleanPathLower)
                return
        }

        MatchedGameList.Push({
            FullRegistryPath: FullKey,
            RegistryKeyName: RegName,
            SoftwareDisplayName: RegName,
            GameInstallPath: CleanPath,
            ScanMethod: "plaync"
        })
    }

    SetRegView 64
    loop reg, SystemPlayNcRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentInstallPath := SafeRegRead(CurrentFullKey, "BaseDir")
        TryAddPlayNcEntry(CurrentFullKey, A_LoopRegName, CurrentInstallPath)
    }

    SetRegView 32
    loop reg, SystemPlayNcRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentInstallPath := SafeRegRead(CurrentFullKey, "BaseDir")
        DisplayKeyString := RegExReplace(CurrentFullKey, "i)^HKEY_LOCAL_MACHINE\\SOFTWARE\\", "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\")
        TryAddPlayNcEntry(DisplayKeyString, A_LoopRegName, CurrentInstallPath)
    }

    SetRegView "Default"
    loop reg, UserPlayNcRoot, "K" {
        CurrentFullKey := A_LoopRegKey . "\" . A_LoopRegName
        CurrentInstallPath := SafeRegRead(CurrentFullKey, "BaseDir")
        TryAddPlayNcEntry(CurrentFullKey, A_LoopRegName, CurrentInstallPath)
    }

    return MatchedGameList
}

ScanGamesFromSteam() {
    SystemSteamRoot := "HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam"
    UserSteamRoot := "HKEY_CURRENT_USER\Software\Valve\Steam"
    MatchedGameList := []

    SteamInstallPaths := []

    TryAddSteamPath(FullKey, RawInstallPath) {
        if (RawInstallPath == "")
            return
        CleanPath := PathUtil.Normalize(RawInstallPath)
        if !DirExist(CleanPath)
            return

        CleanPathLower := StrLower(CleanPath)
        for ExistingPath in SteamInstallPaths {
            if (StrLower(ExistingPath) == CleanPathLower)
                return
        }
        SteamInstallPaths.Push(CleanPath)
    }

    SetRegView 64
    TryAddSteamPath(SystemSteamRoot, SafeRegRead(SystemSteamRoot, "InstallPath"))

    SetRegView 32
    TryAddSteamPath(RegExReplace(SystemSteamRoot, "i)^HKEY_LOCAL_MACHINE\\SOFTWARE\\", "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\"), SafeRegRead(SystemSteamRoot, "InstallPath"))

    SetRegView "Default"
    TryAddSteamPath(UserSteamRoot, SafeRegRead(UserSteamRoot, "SteamPath"))

    SetRegView "Default"

    if (SteamInstallPaths.Length == 0)
        return MatchedGameList

    LibraryPaths := []

    TryAddLibraryPath(RawPath) {
        if (RawPath == "")
            return

        CleanRaw := StrReplace(RawPath, "\\", "\")
        CleanRaw := StrReplace(CleanRaw, '\"', '"')

        if (InStr(CleanRaw, "`n") || InStr(CleanRaw, "`r"))
            return

        CleanPath := PathUtil.Normalize(CleanRaw)

        if !DirExist(CleanPath)
            return

        CleanPathLower := StrLower(CleanPath)
        for ExistingPath in LibraryPaths {
            if (StrLower(ExistingPath) == CleanPathLower)
                return
        }
        LibraryPaths.Push(CleanPath)
    }

    for SteamPath in SteamInstallPaths {
        TryAddLibraryPath(SteamPath)

        LibraryFoldersFile := SteamPath . "\steamapps\libraryfolders.vdf"
        if FileExist(LibraryFoldersFile) {
            try {
                VdfContent := FileRead(LibraryFoldersFile, "UTF-8")

                RegExPattern := 'i)"path"[\t ]+"((?:[^"\\]|\\.)*)"'

                Pos := 1
                while (Pos := RegExMatch(VdfContent, RegExPattern, &Match, Pos)) {
                    TryAddLibraryPath(Match[1])
                    Pos += Match.Len(0)
                }
            }
        }
    }

    for LibPath in LibraryPaths {
        SteamAppsCommon := RTrim(LibPath, "\/") . "\steamapps\common"
        if DirExist(SteamAppsCommon) {
            loop files, SteamAppsCommon . "\*", "D" {
                FolderName := A_LoopFileName
                FullGamePath := PathUtil.Normalize(A_LoopFileFullPath)
                CleanPathLower := StrLower(FullGamePath)

                IsDuplicatePath := false
                for ExistingGame in MatchedGameList {
                    if (StrLower(ExistingGame.GameInstallPath) == CleanPathLower) {
                        IsDuplicatePath := true
                        break
                    }
                }

                if (!IsDuplicatePath) {
                    MatchedGameList.Push({
                        FullRegistryPath: SystemSteamRoot,
                        RegistryKeyName: FolderName,
                        SoftwareDisplayName: FolderName,
                        GameInstallPath: FullGamePath,
                        ScanMethod: "steam"
                    })
                }
            }
        }
    }

    return MatchedGameList
}

; ==============================================================================
; 4. 补丁核心业务逻辑模块
; ==============================================================================

GetLocalPatchInfo() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath

    DefaultResult := Map(
        "isPatched", 0,
        "localVersion", "",
        "branchId", 1,
        "profileKey", "",
        "isInvalidated", false
    )

    if (g_InstallPath == "" || !DirExist(g_InstallPath) || !g_CurrentServer.Has("id"))
        return DefaultResult

    ServerId := g_CurrentServer["id"]
    NormalizedCurrentPath := StrLower(PathUtil.Normalize(g_InstallPath))

    MatchedProfileKey := ""
    MatchedBranchId := 1
    MatchedLocalVersion := ""
    BackupRootDir := ""
    ManifestPath := ""

    for KeyName, ConfigObj in g_ConfigCache.OwnProps() {
        if (SubStr(KeyName, 1, 8) == "Profile_" && Type(ConfigObj) == "Object") {
            if (ConfigObj.HasOwnProp("ServerID") && ConfigObj.ServerID == ServerId) {
                if (ConfigObj.HasOwnProp("InstallPath") && ConfigObj.InstallPath != "" && StrLower(PathUtil.Normalize(ConfigObj.InstallPath)) == NormalizedCurrentPath) {
                    TestBackupDir := PathUtil.Normalize(A_ScriptDir . "\rawBackup\" . KeyName)
                    IsPatchedByBackup := (DirExist(TestBackupDir) && FileExist(TestBackupDir . "\backup_manifest.json"))
                    IsPatchedByConfig := (ConfigObj.HasOwnProp("IsPatched") && ConfigObj.IsPatched == 1)

                    if (IsPatchedByBackup || IsPatchedByConfig) {
                        MatchedProfileKey := KeyName
                        MatchedBranchId := ConfigObj.HasOwnProp("LocalPatchBranchID") ? ConfigObj.LocalPatchBranchID : 1
                        MatchedLocalVersion := ConfigObj.HasOwnProp("LocalPatchVersion") ? ConfigObj.LocalPatchVersion : ""
                        BackupRootDir := TestBackupDir
                        ManifestPath := BackupRootDir . "\backup_manifest.json"
                        break
                    }
                }
            }
        }
    }

    if (MatchedProfileKey == "") {
        BackupBaseDir := PathUtil.Normalize(A_ScriptDir . "\rawBackup")
        if DirExist(BackupBaseDir) {
            loop files, BackupBaseDir . "\*", "D" {
                TestManifest := A_LoopFileFullPath . "\backup_manifest.json"
                if FileExist(TestManifest) {
                    try {
                        Parsed := JSON.parse(FileRead(TestManifest, "UTF-8"))
                        if (Type(Parsed) == "Map" && Parsed.Has("install_path")) {
                            if (StrLower(PathUtil.Normalize(Parsed["install_path"])) == NormalizedCurrentPath) {
                                MatchedProfileKey := A_LoopFileName
                                MatchedBranchId := Parsed.Has("branch_id") ? SafeNumber(Parsed["branch_id"], 1) : 1
                                MatchedLocalVersion := Parsed.Has("patch_version") ? SafeString(Parsed["patch_version"]) : ""
                                BackupRootDir := PathUtil.Normalize(A_LoopFileFullPath)
                                ManifestPath := TestManifest
                                break
                            }
                        }
                    }
                }
            }
        }
    }

    if (MatchedProfileKey == "" && ManifestPath == "")
        return DefaultResult

    if (MatchedLocalVersion == "" && FileExist(ManifestPath)) {
        try {
            Parsed := JSON.parse(FileRead(ManifestPath, "UTF-8"))
            if (Type(Parsed) == "Map" && Parsed.Has("patch_version")) {
                MatchedLocalVersion := SafeString(Parsed["patch_version"])
            }
        }
    }

    IsInvalidated := false

    if (!FileExist(ManifestPath)) {
        IsInvalidated := true
    } else {
        ActionsArray := []
        try {
            ParsedManifest := JSON.parse(FileRead(ManifestPath, "UTF-8"))
            if (Type(ParsedManifest) == "Map" && ParsedManifest.Has("actions") && Type(ParsedManifest["actions"]) == "Array") {
                ActionsArray := ParsedManifest["actions"]
            }
        } catch {
            IsInvalidated := true
        }

        if (!IsInvalidated && ActionsArray.Length == 0) {
            IsInvalidated := true
        }

        if (!IsInvalidated) {
            loop ActionsArray.Length {
                Act := ActionsArray[A_Index]
                RelPath := SafeGet(Act, "target_relative_path", "")

                if (RelPath == "" || InStr(RelPath, ".."))
                    continue

                ActType := SafeString(SafeGet(Act, "type", "add"), "add")
                TargetPath := ResolveTargetPath(RelPath)
                ExpectedMd5 := StrLower(SafeString(SafeGet(Act, "file_md5", "")))

                if (ActType == "run") {
                    if (!FileExist(TargetPath)) {
                        IsInvalidated := true
                        break
                    }
                }
                else if (ActType == "add") {
                    if (!FileExist(TargetPath)) {
                        IsInvalidated := true
                        break
                    }
                }
                else if (ActType == "replace") {
                    if (!FileExist(TargetPath)) {
                        IsInvalidated := true
                        break
                    }
                    if (ExpectedMd5 != "" && ExpectedMd5 != "d41d8cd98f00b204e9800998ecf8427e") {
                        if (HashFileMd5(TargetPath) != ExpectedMd5) {
                            IsInvalidated := true
                            break
                        }
                    }
                }
                else if (ActType == "delete") {
                    if (FileExist(TargetPath)) {
                        IsInvalidated := true
                        break
                    }
                }
            }
        }
    }

    if (IsInvalidated) {
        if (MatchedProfileKey != "" && g_ConfigCache.HasOwnProp(MatchedProfileKey)) {
            g_ConfigCache.%MatchedProfileKey%.IsPatched := 0
            g_ConfigCache.%MatchedProfileKey%.LocalPatchVersion := ""
            g_ConfigCache.%MatchedProfileKey%.LocalPatchBranchID := 0
        }

        SaveAllConfig()

        return Map(
            "isPatched", 0,
            "localVersion", "",
            "branchId", MatchedBranchId,
            "profileKey", MatchedProfileKey,
            "isInvalidated", true
        )
    }

    return Map(
        "isPatched", 1,
        "localVersion", MatchedLocalVersion,
        "branchId", MatchedBranchId,
        "profileKey", MatchedProfileKey,
        "isInvalidated", false
    )
}

GetPatchUpdates(ServerMap) {
    UpdatesList := []
    if (Type(ServerMap) != "Map" || !ServerMap.Has("patch_branches"))
        return UpdatesList

    LocalInfo := GetLocalPatchInfo()
    if (LocalInfo["isPatched"] == 0 || LocalInfo["localVersion"] == "")
        return UpdatesList

    for Branch in ServerMap["patch_branches"] {
        BranchId := Branch["id"]
        if (BranchId == LocalInfo["branchId"]) {
            LatestVer := Branch.Has("latest_patch_version") ? SafeString(Branch["latest_patch_version"]) : "1.0.0.0"
            if (VerCompare(LatestVer, LocalInfo["localVersion"]) > 0) {
                UpdatesList.Push({
                    Branch: Branch,
                    LocalVersion: LocalInfo["localVersion"],
                    LatestVersion: LatestVer
                })
            }
        }
    }

    return UpdatesList
}

CheckPatchUpdate(ServerMap, OnComplete := "") {
    global g_IsPatching

    if (Type(ServerMap) != "Map" || !ServerMap.Has("patch_branches")) {
        if (OnComplete)
            OnComplete()
        return
    }

    UpdatesList := GetPatchUpdates(ServerMap)
    if (UpdatesList.Length > 0 && !g_IsPatching) {
        g_IsPatching := true
        RefreshUi()

        DialogCallback(selected) {
            HandleUpdateBranchSelected(selected)
            if (OnComplete)
                OnComplete()
        }

        ShowMultiBranchDialog(UpdatesList, DialogCallback, true)
    } else {
        if (OnComplete)
            OnComplete()
    }
}

DoChinesePatch(*) {
    global g_InstallPath, g_CurrentServer, BtnChinese, g_IsPatching

    if (!g_InstallPath || !DirExist(g_InstallPath)) {
        ShowMessageDialog("先设置 AION2 游戏的安装目录。")
        RefreshUi()
        return
    }

    Branches := g_CurrentServer["patch_branches"]
    if (Branches.Length == 0) {
        ShowMessageDialog("未发现有效的汉化补丁数据。")
        RefreshUi()
        return
    }

    g_IsPatching := true
    BtnChinese.Opt("+Disabled")

    ShowMultiBranchDialog(Branches, HandleChineseBranchSelected, false)
}

HandleChineseBranchSelected(SelectedBranch) {
    global g_IsPatching
    if (!SelectedBranch) {
        g_IsPatching := false
        RefreshUi()
        return
    }
    ExecuteChinesePatch(SelectedBranch, false)
}

ExecuteChinesePatch(PatchBranch, IsUpdate := false) {
    global g_InstallPath, g_IsPatching

    try {
        KillProcessByFullPath()

        if (IsUpdate) {
            DoRestorePatchInternal(true)
        }

        ActionsArray := PatchBranch["actions"]
        if (ActionsArray.Length == 0) {
            ShowMessageDialog(IsUpdate ? "更新汉化补丁操作执行失败：`r`n`r`n未发现有效的汉化补丁执行方案。" : "未发现有效的汉化补丁执行方案。")
            g_IsPatching := false
            return
        }

        BranchId := PatchBranch["id"]
        HasAnyInstalled := false

        for Act in ActionsArray {
            RelPath := SafeGet(Act, "target_relative_path", "")
            if InStr(RelPath, "..")
                continue

            ActType := Act.Has("type") ? Act["type"] : "add"
            TargetMd5 := StrLower(SafeString(SafeGet(Act, "file_md5", "")))

            if (ActType != "add" && ActType != "replace" && ActType != "run")
                continue

            TargetPath := ResolveTargetPath(RelPath)

            if FileExist(TargetPath) {
                if (ActType == "replace") {
                    if (TargetMd5 != "" && HashFileMd5(TargetPath) == TargetMd5) {
                        HasAnyInstalled := true
                        break
                    }
                } else if (ActType == "add") {
                    HasAnyInstalled := true
                    break
                }
            }
        }

        if (HasAnyInstalled && !IsUpdate) {
            ContextMap := Map("branch", PatchBranch, "actions", ActionsArray, "branchId", BranchId, "isUpdate", IsUpdate)
            ShowConfirmDialog("检测到汉化补丁文件，是否直接覆盖？", (IsConfirmed) => HandleOverlapConfirmation(IsConfirmed, ContextMap))
        } else {
            ApplyPatchBranch(PatchBranch, ActionsArray, BranchId, IsUpdate)
        }
    } catch Error as Err {
        ErrMsg := IsUpdate ? ("更新汉化补丁操作执行失败：`r`n`r`n" . Err.Message) : ("汉化发生未知错误：`r`n`r`n" . Err.Message)
        ShowMessageDialog(ErrMsg)
        g_IsPatching := false
        RefreshUi()
    }
}

HandleOverlapConfirmation(IsConfirmed, ContextMap) {
    global g_IsPatching
    if (IsConfirmed) {
        ApplyPatchBranch(ContextMap["branch"], ContextMap["actions"], ContextMap["branchId"], ContextMap["isUpdate"])
    } else {
        g_IsPatching := false
        RefreshUi()
    }
}

ApplyPatchBranch(PatchBranch, ActionsArray, BranchId, IsUpdate := false) {
    global g_InstallPath, g_CurrentServer, g_PatchesCacheDir, g_ConfigCache, g_ProjectName, g_IsPatching, MainStatusBar

    try {
        ServerId := g_CurrentServer.Has("id") ? g_CurrentServer["id"] : "default"
        NormalizedInstallPath := PathUtil.Normalize(g_InstallPath)

        ProfileKey := GetProfileKey(ServerId, NormalizedInstallPath, BranchId)
        BackupRootDir := GetBackupRootDir(ServerId, NormalizedInstallPath, BranchId)
        BackupTextFile := A_ScriptDir . "\rawBackup\" . g_ProjectName . " 备份文件夹.txt"

        LocalCacheRootDir := PathUtil.Normalize(A_ScriptDir . "\" . g_PatchesCacheDir)
        if !DirExist(LocalCacheRootDir)
            DirCreate(LocalCacheRootDir)

        TempDownloadList := Map()
        SetStatusBarText()
        MainStatusBar.SetText("`t正在检查本地缓存的文件 MD5…")
        AllLocalCacheValid := true

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            ActType := SafeGet(Act, "type", "add")
            if (ActType != "add" && ActType != "replace" && ActType != "run") || (Act["file_md5"] == "d41d8cd98f00b204e9800998ecf8427e")
                continue

            LocalCacheFile := GetLocalCachePath(Act)
            KeyName := Act["remote_filename"]

            if (FileExist(LocalCacheFile) && Act["file_md5"] != "" && HashFileMd5(LocalCacheFile) == Act["file_md5"]) {
                TempDownloadList[KeyName] := Map("src", LocalCacheFile, "fileAction", Act)
            } else {
                AllLocalCacheValid := false
            }
        }

        if (!AllLocalCacheValid)
            SelectFastestMirrorNode()
        else
            SetStatusBarText("本地缓存全部校验通过，已跳过网络下载。")

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            ActType := SafeGet(Act, "type", "add")
            if (ActType != "add" && ActType != "replace" && ActType != "run") || (Act["file_md5"] == "d41d8cd98f00b204e9800998ecf8427e")
                continue

            KeyName := Act["remote_filename"]
            if TempDownloadList.Has(KeyName)
                continue

            RemoteFileUrl := Act["remote_filename"]
            LocalCacheFile := GetLocalCachePath(Act)

            SplitPath(LocalCacheFile, &SafeFilename, , &SafeExt)
            RandomSuffix := A_TickCount . "_" . Random(1000, 9999)
            TmpFile := PathUtil.Normalize(A_Temp . "\" . SafeFilename . "_" . RandomSuffix . ".tmp")
            if FileExist(TmpFile)
                FileDelete(TmpFile)

            if (!DownloadPatchFileAsync(RemoteFileUrl, TmpFile, Act)) {
                if FileExist(TmpFile)
                    FileDelete(TmpFile)
                throw Error("汉化补丁文件 [" . Act["filename"] . "] 下载失败。")
            }

            if (Act["file_md5"] != "" && HashFileMd5(TmpFile) != Act["file_md5"]) {
                if FileExist(TmpFile)
                    FileDelete(TmpFile)
                throw Error("文件 [" . Act["filename"] . "] MD5 不匹配，汉化补丁文件下载失败。")
            }

            if FileExist(LocalCacheFile)
                FileDelete(LocalCacheFile)
            FileMove(TmpFile, LocalCacheFile, 1)

            SetStatusBarText("文件 [" . Act["filename"] . "] 下载并校验完成。")
            TempDownloadList[KeyName] := Map("src", LocalCacheFile, "fileAction", Act)
        }

        if !DirExist(BackupRootDir)
            DirCreate(BackupRootDir)

        if !FileExist(BackupTextFile)
            FileAppend("", BackupTextFile, "UTF-8-RAW")

        ManifestMap := Map(
            "server_id", ServerId,
            "branch_id", BranchId,
            "install_path", NormalizedInstallPath,
            "patch_version", PatchBranch["latest_patch_version"],
            "actions", ActionsArray
        )
        WriteFileAtomic(BackupRootDir . "\backup_manifest.json", JSON.stringify(ManifestMap))

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            RelPath := Act["target_relative_path"]

            if InStr(RelPath, "..")
                throw Error("非法配置：路径包含非法相对级别跳转 [" . RelPath . "]")

            FinalPath := ResolveTargetPath(RelPath)
            BackupPath := PathUtil.Normalize(BackupRootDir . "\" . RelPath)
            SplitPath(FinalPath, , &FDir)
            SplitPath(BackupPath, , &BDir)

            if (Act["type"] == "remove") {
                if FileExist(FinalPath)
                    FileDelete(FinalPath)

            } else if (Act["type"] == "delete") {
                if FileExist(FinalPath) {
                    if (BDir != "" && !DirExist(BDir))
                        DirCreate(BDir)
                    if (!FileExist(BackupPath))
                        FileCopy(FinalPath, BackupPath, 1)
                    FileDelete(FinalPath)
                }

            } else if (Act["type"] == "add" || Act["type"] == "replace" || Act["type"] == "run") {
                if (Act["file_md5"] == "d41d8cd98f00b204e9800998ecf8427e") {
                    if (FDir != "" && !DirExist(FDir))
                        DirCreate(FDir)

                    if (Act["type"] == "replace" && FileExist(FinalPath)) {
                        if (BDir != "" && !DirExist(BDir))
                            DirCreate(BDir)
                        if (!FileExist(BackupPath)) {
                            FileCopy(FinalPath, BackupPath, 1)
                        }
                    }
                    WriteFileAtomic(FinalPath, "")
                } else {
                    KeyName := Act["remote_filename"]
                    if (TempDownloadList.Has(KeyName)) {
                        if (FDir != "" && !DirExist(FDir))
                            DirCreate(FDir)

                        if (Act["type"] == "replace" && FileExist(FinalPath)) {
                            if (BDir != "" && !DirExist(BDir))
                                DirCreate(BDir)
                            if (!FileExist(BackupPath)) {
                                FileCopy(FinalPath, BackupPath, 1)
                            }
                        }

                        FileCopy(TempDownloadList[KeyName]["src"], FinalPath, 1)
                    }
                }
            }
        }

        LaunchRunActions(ActionsArray)

        g_ConfigCache.%ProfileKey% := {
            ServerID: ServerId,
            BranchID: BranchId,
            InstallPath: NormalizedInstallPath,
            IsPatched: 1,
            LocalPatchVersion: PatchBranch["latest_patch_version"],
            LocalPatchBranchID: BranchId
        }
        SaveAllConfig()

        SetStatusBarText()
        SuccMsg := IsUpdate ? "汉化补丁已更新至最新版本。`r`n`r`n更新完成。" : "汉化补丁文件已成功释放至游戏目录。`r`n`r`n汉化完成。"
        ShowMessageDialog(SuccMsg)
    } catch Error as Err {
        SetStatusBarText()
        FailMsg := IsUpdate ? ("更新汉化补丁操作执行失败：`r`n`r`n" . Err.Message . "`r`n`r`n建议在 PURPLE 或 Steam 中执行文件完整性校验。")
            : ("汉化操作执行失败：`r`n`r`n" . Err.Message . "`r`n`r`n建议在 PURPLE 或 Steam 中执行文件完整性校验。")
        ShowMessageDialog(FailMsg)
    } finally {
        g_IsPatching := false
        RefreshUi()
    }
}

DoUpdatePatch(*) {
    global g_InstallPath, g_IsPatching, g_CurrentServer

    if (!g_InstallPath || !DirExist(g_InstallPath)) {
        ShowMessageDialog("先设置 AION2 游戏的安装目录。")
        RefreshUi()
        return
    }

    UpdateBranches := GetPatchUpdates(g_CurrentServer)
    if (UpdateBranches.Length == 0) {
        ShowMessageDialog("当前无需要更新的汉化补丁。")
        RefreshUi()
        return
    }

    g_IsPatching := true
    RefreshUi()

    ShowMultiBranchDialog(UpdateBranches, HandleUpdateBranchSelected, true)
}

HandleUpdateBranchSelected(SelectedBranch) {
    global g_IsPatching
    if (!SelectedBranch) {
        g_IsPatching := false
        RefreshUi()
        return
    }
    ExecuteChinesePatch(SelectedBranch, true)
}

DoRestorePatch(*) {
    global g_IsPatching
    g_IsPatching := true
    RefreshUi()

    try {
        DoRestorePatchInternal(false)
    } catch Error as Err {
        SetStatusBarText()
        ShowMessageDialog(Err.Message)
    } finally {
        g_IsPatching := false
        RefreshUi()
    }
}

DoRestorePatchInternal(IsSilent := false) {
    global g_InstallPath, g_CurrentServer, g_ConfigCache

    if (!g_InstallPath || !DirExist(g_InstallPath))
        throw Error("先设置 AION2 游戏的安装目录。")

    KillProcessByFullPath()

    ServerId := g_CurrentServer.Has("id") ? g_CurrentServer["id"] : "default"
    NormalizedInstallPath := PathUtil.Normalize(g_InstallPath)

    LocalManifestPath := ""
    BackupRootDir := ""
    ProfileKey := ""
    SavedBranchID := 1

    BackupBaseDir := PathUtil.Normalize(A_ScriptDir . "\rawBackup")
    if DirExist(BackupBaseDir) {
        loop files, BackupBaseDir . "\*", "D" {
            FolderName := A_LoopFileName
            if (SubStr(FolderName, 1, 8) == "Profile_") {
                TestManifestPath := A_LoopFileFullPath . "\backup_manifest.json"
                if FileExist(TestManifestPath) {
                    try {
                        ParsedTmp := JSON.parse(FileRead(TestManifestPath, "UTF-8"))
                        if (Type(ParsedTmp) == "Map" && ParsedTmp.Has("install_path")) {
                            if (StrLower(PathUtil.Normalize(ParsedTmp["install_path"])) == StrLower(NormalizedInstallPath)) {
                                ProfileKey := FolderName
                                BackupRootDir := PathUtil.Normalize(A_LoopFileFullPath)
                                LocalManifestPath := TestManifestPath
                                if (ParsedTmp.Has("branch_id"))
                                    SavedBranchID := SafeNumber(ParsedTmp["branch_id"], 1)
                                if (ParsedTmp.Has("server_id"))
                                    ServerId := ParsedTmp["server_id"]
                                break
                            }
                        }
                    }
                }
            }
        }
    }

    if (LocalManifestPath == "") {
        SavedBranchID := GetSavedBranchID()
        ProfileKey := GetProfileKey(ServerId, NormalizedInstallPath, SavedBranchID)
        BackupRootDir := GetBackupRootDir(ServerId, NormalizedInstallPath, SavedBranchID)
        LocalManifestPath := BackupRootDir . "\backup_manifest.json"
    }

    ActionsArray := []
    PatchBranch := ""

    if FileExist(LocalManifestPath) {
        try {
            Parsed := JSON.parse(FileRead(LocalManifestPath, "UTF-8"))
            if (Type(Parsed) == "Map" && Parsed.Has("actions") && Type(Parsed["actions"]) == "Array") {
                ActionsArray := Parsed["actions"]
            }
        }
    }

    if (ActionsArray.Length == 0) {
        Branches := g_CurrentServer["patch_branches"]
        if (Branches.Length == 0)
            throw Error("当前服务器未发现可用的撤销配置。")

        for Branch in Branches {
            if (Branch["id"] == SavedBranchID) {
                PatchBranch := Branch
                break
            }
        }
        if (!PatchBranch && Branches.Length > 0)
            PatchBranch := Branches[1]

        if (PatchBranch && PatchBranch.Has("actions"))
            ActionsArray := PatchBranch["actions"]
    }

    if (ActionsArray.Length == 0)
        throw Error("当前汉化补丁配置异常，缺少撤销执行动作及备份清单。")

    HasAnyPatchFile := false
    loop ActionsArray.Length {
        Act := ActionsArray[A_Index]
        RelPath := SafeGet(Act, "target_relative_path", "")

        if InStr(RelPath, "..")
            continue

        ActType := Act.Has("type") ? Act["type"] : "add"
        TargetPath := ResolveTargetPath(RelPath)
        BackupPath := PathUtil.Normalize(BackupRootDir . "\" . RelPath)
        if (ActType == "add" || ActType == "run") {
            if FileExist(TargetPath) {
                HasAnyPatchFile := true
                break
            }
        } else if (ActType == "replace" || ActType == "delete") {
            if FileExist(BackupPath) {
                HasAnyPatchFile := true
                break
            }
        }
    }

    Info := GetLocalPatchInfo()
    IsPatched := Info["isPatched"]

    if (IsPatched == 0 && !HasAnyPatchFile && !DirExist(BackupRootDir)) {
        if (!IsSilent)
            throw Error("当前游戏未应用汉化，无需执行撤销操作。")
        return
    }

    if (IsPatched == 1 && !HasAnyPatchFile && !DirExist(BackupRootDir)) {
        if (ProfileKey != "" && g_ConfigCache.HasOwnProp(ProfileKey)) {
            g_ConfigCache.%ProfileKey%.IsPatched := 0
            g_ConfigCache.%ProfileKey%.LocalPatchVersion := ""
            g_ConfigCache.%ProfileKey%.LocalPatchBranchID := 0
            SaveAllConfig()
        }
        if (!IsSilent)
            throw Error("未检测到汉化补丁文件，已重置配置状态。")
        return
    }

    FailedFiles := []

    loop ActionsArray.Length {
        Act := ActionsArray[A_Index]
        RelPath := SafeGet(Act, "target_relative_path", "")

        if InStr(RelPath, "..")
            continue

        ActType := Act.Has("type") ? Act["type"] : "add"

        if (ActType == "run") {
            FinalPath := ResolveTargetPath(RelPath)
            if FileExist(FinalPath) {
                try {
                    FileDelete(FinalPath)
                } catch {
                    FailedFiles.Push(RelPath)
                }
            }
        }
    }

    loop ActionsArray.Length {
        Act := ActionsArray[A_Index]
        RelPath := SafeGet(Act, "target_relative_path", "")

        if InStr(RelPath, "..")
            continue

        ActType := Act.Has("type") ? Act["type"] : "add"

        if (ActType == "run")
            continue

        FinalPath := ResolveTargetPath(RelPath)
        BackupPath := PathUtil.Normalize(BackupRootDir . "\" . RelPath)
        SplitPath(FinalPath, , &FDir)

        if (ActType == "add") {
            if FileExist(FinalPath) {
                try {
                    FileDelete(FinalPath)
                } catch {
                    FailedFiles.Push(RelPath)
                }
            }
        }
        else if (ActType == "replace" || ActType == "delete") {
            if (!FileExist(BackupPath)) {
                continue
            }

            if (FDir != "" && !DirExist(FDir)) {
                try {
                    DirCreate(FDir)
                } catch {
                    FailedFiles.Push(RelPath)
                    continue
                }
            }

            try {
                FileCopy(BackupPath, FinalPath, 1)
                try FileDelete(BackupPath)
            } catch {
                FailedFiles.Push(RelPath)
            }
        }
    }

    if (ProfileKey != "") {
        if (!g_ConfigCache.HasOwnProp(ProfileKey))
            g_ConfigCache.%ProfileKey% := {}
        g_ConfigCache.%ProfileKey%.IsPatched := 0
        g_ConfigCache.%ProfileKey%.LocalPatchVersion := ""
        g_ConfigCache.%ProfileKey%.LocalPatchBranchID := 0
        SaveAllConfig()
    }

    if (FailedFiles.Length == 0 && DirExist(BackupRootDir)) {
        try DirDelete(BackupRootDir, 1)
    }

    if (FailedFiles.Length > 0) {
        FailMessage := "部分备份文件还原失败，建议在 PURPLE 或 Steam 中执行文件完整性校验。"
        if (!IsSilent)
            ShowMessageDialog(FailMessage)
        else
            throw Error(FailMessage)
        return
    }

    if (!IsSilent)
        ShowMessageDialog("已清除汉化补丁，恢复游戏默认语言。`r`n`r`n撤销完成。")
}

OnBtnRefreshStatusClick(*) {
    Info := GetLocalPatchInfo()
    launchedCount := 0

    if (Info["isPatched"] == 1 && Info["profileKey"] != "") {
        BackupRootDir := PathUtil.Normalize(A_ScriptDir . "\rawBackup\" . Info["profileKey"])
        ManifestPath := BackupRootDir . "\backup_manifest.json"
        if FileExist(ManifestPath) {
            try {
                Parsed := JSON.parse(FileRead(ManifestPath, "UTF-8"))
                if (Type(Parsed) == "Map" && Parsed.Has("actions")) {
                    launchedCount := LaunchRunActions(Parsed["actions"])
                }
            }
        }
    }

    RefreshUi()

    if (Info["isInvalidated"]) {
        SetStatusBarText("检测到汉化文件失效，已重置按钮状态。")
    } else if (Info["isPatched"] == 1) {
        if (launchedCount > 0)
            SetStatusBarText("汉化补丁状态正常，已自动唤醒 " . launchedCount . " 个依赖程序。")
        else
            SetStatusBarText("汉化补丁状态正常。")
    } else {
        SetStatusBarText("当前未安装汉化补丁或已重置。")
    }
}

; ==============================================================================
; 5. 进程控制与程序运行模块
; ==============================================================================

IsGameProcessRunning() {
    global g_GlobalConfigData, g_DefaultGameProcesses

    ProcessList := g_DefaultGameProcesses
    if (Type(g_GlobalConfigData) == "Map" && g_GlobalConfigData.Has("game_processes")) {
        ConfigList := g_GlobalConfigData["game_processes"]
        if (Type(ConfigList) == "Array" && ConfigList.Length > 0) {
            ProcessList := ConfigList
        }
    }

    for ProcName in ProcessList {
        StrProc := SafeString(ProcName)
        if (StrProc != "" && ProcessExist(StrProc)) {
            return true
        }
    }

    return false
}

ResolveTargetPath(RelPath) {
    global g_InstallPath

    CleanPath := StrReplace(RelPath, "/", "\")
    CleanPath := LTrim(CleanPath, "\")

    CleanPath := StrReplace(CleanPath, "{AppDir}", A_ScriptDir, false)
    CleanPath := StrReplace(CleanPath, "{Temp}", A_Temp, false)
    CleanPath := StrReplace(CleanPath, "{AppData}", A_AppData, false)
    CleanPath := StrReplace(CleanPath, "{LocalAppData}", A_AppData . "\..", false)

    Pos := 1
    while (Pos := RegExMatch(CleanPath, "i)%([^%]+)%", &Match, Pos)) {
        EnvVal := EnvGet(Match[1])
        CleanPath := StrReplace(CleanPath, Match[0], EnvVal, false)
        Pos += StrLen(EnvVal)
    }

    if InStr(CleanPath, ":") {
        return PathUtil.Normalize(CleanPath)
    }

    return PathUtil.Normalize(g_InstallPath . "\" . CleanPath)
}

RunTargetProgram(FullPath, IsHide := false) {
    if !FileExist(FullPath)
        return

    SplitPath(FullPath, , &WorkDir)
    RunOptions := IsHide ? "Hide" : ""

    try {
        Run(FullPath, WorkDir, RunOptions)
    }
}

LaunchRunActions(ActionsArray) {
    launched := 0
    if (Type(ActionsArray) != "Array")
        return launched

    for Act in ActionsArray {
        if (Type(Act) != "Map")
            continue
        ActType := SafeGet(Act, "type", "add")
        if (ActType == "run") {
            RelPath := SafeGet(Act, "target_relative_path", "")
            if (RelPath == "" || InStr(RelPath, ".."))
                continue

            TargetPath := ResolveTargetPath(RelPath)
            if FileExist(TargetPath) {
                SplitPath(TargetPath, &ExeName)
                if (!ProcessExist(ExeName)) {
                    IsHide := Act.Has("hide") ? Act["hide"] : false
                    RunTargetProgram(TargetPath, IsHide)
                    launched++
                }
            }
        }
    }
    return launched
}

KillProcessByFullPath() {
    global g_CurrentServer, g_InstallPath

    if (!g_InstallPath || !DirExist(g_InstallPath))
        return

    ServerId := g_CurrentServer.Has("id") ? g_CurrentServer["id"] : "default"
    NormalizedInstallPath := StrLower(PathUtil.Normalize(g_InstallPath))
    SavedBranchID := GetSavedBranchID()

    BackupRootDir := GetBackupRootDir(ServerId, NormalizedInstallPath, SavedBranchID)
    LocalManifestPath := BackupRootDir . "\backup_manifest.json"

    ActionsArray := []
    if FileExist(LocalManifestPath) {
        try {
            Parsed := JSON.parse(FileRead(LocalManifestPath, "UTF-8"))
            if (Type(Parsed) == "Map" && Parsed.Has("actions") && Type(Parsed["actions"]) == "Array") {
                ActionsArray := Parsed["actions"]
            }
        }
    }

    if (ActionsArray.Length == 0 && g_CurrentServer.Has("patch_branches")) {
        for Branch in g_CurrentServer["patch_branches"] {
            if (Branch.Has("actions") && Type(Branch["actions"]) == "Array") {
                for Act in Branch["actions"] {
                    ActionsArray.Push(Act)
                }
            }
        }
    }

    TargetRunFiles := Map()
    for Act in ActionsArray {
        ActType := SafeString(SafeGet(Act, "type", ""))
        RelPath := SafeString(SafeGet(Act, "target_relative_path", ""))

        if (ActType == "run" && RelPath != "") {
            ResolvedPath := ResolveTargetPath(RelPath)
            TargetRunFiles[StrLower(PathUtil.Normalize(ResolvedPath))] := true
        }
    }

    if (TargetRunFiles.Count == 0)
        return

    currentPid := DllCall("Kernel32.dll\GetCurrentProcessId", "UInt")
    killedByAPI := false

    try {
        hSnapshot := DllCall("Kernel32.dll\CreateToolhelp32Snapshot", "UInt", 0x02, "UInt", 0, "Ptr")
        if (hSnapshot != -1) {
            bufSize := (A_PtrSize = 8) ? 568 : 556
            PROCESSENTRY32 := Buffer(bufSize, 0)
            NumPut("UInt", bufSize, PROCESSENTRY32, 0)

            killedCount := 0
            if DllCall("Kernel32.dll\Process32First", "Ptr", hSnapshot, "Ptr", PROCESSENTRY32) {
                Loop {
                    procID := NumGet(PROCESSENTRY32, 8, "UInt")
                    if (procID != currentPid) {
                        try {
                            rawPath := ProcessGetPath(procID)
                            if (rawPath != "") {
                                procPath := StrLower(PathUtil.Normalize(rawPath))
                                if TargetRunFiles.Has(procPath) {
                                    try {
                                        ProcessClose(procID)
                                        killedCount++
                                    }
                                }
                            }
                        }
                    }
                } until !DllCall("Kernel32.dll\Process32Next", "Ptr", hSnapshot, "Ptr", PROCESSENTRY32)
            }
            DllCall("Kernel32.dll\CloseHandle", "Ptr", hSnapshot)

            if (killedCount > 0)
                killedByAPI := true
        }
    } catch {
        killedByAPI := false
    }

    if (!killedByAPI) {
        try {
            wmi := ComObjGet("winmgmts:\\.\root\cimv2")
            query := wmi.ExecQuery("SELECT ProcessId, ExecutablePath FROM Win32_Process WHERE ExecutablePath IS NOT NULL")

            for item in query {
                if (item.ExecutablePath != "" && item.ProcessId != currentPid) {
                    ProcPath := StrLower(PathUtil.Normalize(item.ExecutablePath))
                    if TargetRunFiles.Has(ProcPath) {
                        try ProcessClose(item.ProcessId)
                    }
                }
            }
            killedByAPI := true
        } catch {
            killedByAPI := false
        }
    }

    if (!killedByAPI) {
        try {
            targetExeNames := Map()
            for targetPath, _ in TargetRunFiles {
                SplitPath(targetPath, &exeName)
                if (exeName != "")
                    targetExeNames[StrLower(exeName)] := true
            }

            for exeName, _ in targetExeNames {
                while (pid := ProcessExist(exeName)) {
                    if (pid == currentPid)
                        break

                    try ProcessClose(pid)
                    catch
                        break
                }
            }
        }
    }
}

; ==============================================================================
; 6. 网络测速、下载与更新检查模块
; ==============================================================================

SelectFastestMirrorNode() {
    global g_CleanPreUrl, g_PatchManifestFilename, g_CleanProxyMirrors, MainStatusBar, g_BestDownloadPrefix, g_BestLatency

    Candidates := [
        {
            Prefix: "",
            TestUrl: g_CleanPreUrl . "/" . g_PatchManifestFilename
        }
    ]
    for Mirror in g_CleanProxyMirrors {
        Candidates.Push({
            Prefix: Mirror,
            TestUrl: Mirror . "/" . g_CleanPreUrl . "/" . g_PatchManifestFilename
        })
    }

    SetStatusBarText()
    MainStatusBar.SetText("`t正在对代理进行网络测速…")

    ReqList := []
    for Candidate in Candidates {
        try {
            whr := WinHttpRequest()
            whr.Open("HEAD", Candidate.TestUrl, true)
            whr.SetRequestHeader("User-Agent", "Mozilla/5.0")
            ReqList.Push({
                req: whr,
                prefix: Candidate.Prefix,
                startTime: A_TickCount,
                finished: false,
                latency: 99999
            })
            whr.Send()
        } catch {
            continue
        }
    }

    g_BestLatency := 99999
    g_BestDownloadPrefix := ""
    MaxWaitMs := 3000
    StartWait := A_TickCount

    while (A_TickCount - StartWait < MaxWaitMs) {
        AllFinished := true
        for item in ReqList {
            if item.finished
                continue
            try {
                if item.req.WaitForResponse(0.01) {
                    item.finished := true
                    if (item.req.Status == 200 || item.req.Status == 301 || item.req.Status == 302) {
                        item.latency := A_TickCount - item.startTime
                        if (item.latency < g_BestLatency) {
                            g_BestLatency := item.latency
                            g_BestDownloadPrefix := item.prefix
                        }
                    }
                } else {
                    AllFinished := false
                }
            } catch {
                item.finished := true
            }
        }
        if (g_BestLatency < 500 || AllFinished)
            break
        Sleep(30)
    }

    if (g_BestLatency >= 99999) {
        throw Error("所有下载节点连接超时，检查网络或开启加速器。")
    }

    return g_BestDownloadPrefix
}

DownloadPatchFileAsync(RemoteFileUrl, DestPath, FileAction) {
    global g_CleanPreUrl, g_BestDownloadPrefix, g_BestLatency, MainStatusBar

    CleanRemotePath := StrReplace(RemoteFileUrl, "\", "/")
    CleanRemotePath := RegExReplace(CleanRemotePath, "i)^https?://", "")
    CleanRemotePath := LTrim(CleanRemotePath, "/")

    TargetUrl := (g_BestDownloadPrefix != "") ? g_BestDownloadPrefix . "/" . g_CleanPreUrl . "/" . CleanRemotePath : g_CleanPreUrl . "/" . CleanRemotePath

    TotalBytes := SafeNumber(FileAction["file_size"], 0)

    SplitPath(DestPath, , &ParentDir)
    if (ParentDir != "" && !DirExist(ParentDir))
        DirCreate(ParentDir)
    if FileExist(DestPath) {
        try FileDelete(DestPath)
        catch {
            return false
        }
    }

    isDone := false
    hasError := false
    errMsg := ""

    OnFinishedCallback(result) {
        if (result is OSError || result is Error) {
            hasError := true
            errMsg := result.Message
        }
        isDone := true
    }

    OnProgressCallback(downloaded, total) {
        if (total > 0 && TotalBytes <= 0)
            TotalBytes := total

        CurrentSizeStr := FormatFileSize(downloaded)
        TotalStr := (TotalBytes > 0) ? FormatFileSize(TotalBytes) : "未知大小"

        StatusText := Format("`t正在下载：{} [{} / {}] (节点: {}ms)", FileAction["filename"], CurrentSizeStr, TotalStr, g_BestLatency)
        SetStatusBarText()
        MainStatusBar.SetText(StatusText)
    }

    SetStatusBarText()
    MainStatusBar.SetText(Format("`t开始下载：{} (节点: {}ms)", FileAction["filename"], g_BestLatency))

    try {
        req := DownloadAsync(TargetUrl, DestPath, OnFinishedCallback, OnProgressCallback)
    } catch {
        return false
    }

    while (!isDone) {
        Sleep(50)
    }

    if (hasError || !FileExist(DestPath) || FileGetSize(DestPath) == 0)
        return false

    return true
}

HttpGetText(ApiUrl, TimeoutSeconds := 5) {
    try {
        Whr := WinHttpRequest()
        Whr.Open("GET", ApiUrl, true)
        Whr.SetRequestHeader("User-Agent", "Mozilla/5.0")
        Whr.Send()
        if (Whr.WaitForResponse(TimeoutSeconds)) {
            if (Whr.Status == 200)
                return Whr.ResponseText
        }
    } catch {
        return ""
    }
    return ""
}

CheckClientUpdate(UpdateMap, OnComplete := "") {
    global g_CurrentAppVersion

    if (Type(UpdateMap) != "Map" || !UpdateMap.Has("latest_client_version")) {
        if (OnComplete)
            OnComplete()
        return
    }

    LatestVersion := SafeString(UpdateMap["latest_client_version"])
    MinRequiredVersion := UpdateMap.Has("min_required_version") ? SafeString(UpdateMap["min_required_version"]) : ""
    ChangelogText := UpdateMap.Has("changelog") ? SafeString(UpdateMap["changelog"]) : ""

    IsForceUpdate := (MinRequiredVersion != "" && VerCompare(MinRequiredVersion, g_CurrentAppVersion) > 0)
    HasNewVersion := (LatestVersion != "" && VerCompare(LatestVersion, g_CurrentAppVersion) > 0)

    if (IsForceUpdate || HasNewVersion) {
        DownloadUrlMain := UpdateMap.Has("client_download_url_main") ? SafeString(UpdateMap["client_download_url_main"]) : ""
        DownloadUrlMinor := UpdateMap.Has("client_download_url_minor") ? SafeString(UpdateMap["client_download_url_minor"]) : ""

        ShowAppUpdateDialog(ChangelogText, DownloadUrlMain, DownloadUrlMinor, IsForceUpdate, OnComplete)
    } else {
        if (OnComplete)
            OnComplete()
    }
}

CheckBulletin(BulletinMap, OnComplete := "") {
    global g_LastSeenBulletinVersion

    if (Type(BulletinMap) != "Map" || !BulletinMap.Has("latest_bulletin_version")) {
        if (OnComplete)
            OnComplete()
        return
    }

    LatestVersion := SafeString(BulletinMap["latest_bulletin_version"])
    BulletinText := BulletinMap.Has("changelog") ? SafeString(BulletinMap["changelog"]) : ""

    if (LatestVersion != "" && VerCompare(LatestVersion, g_LastSeenBulletinVersion) > 0 && BulletinText != "") {
        ShowBulletinDialog(BulletinText, LatestVersion, OnComplete)
    } else {
        if (OnComplete)
            OnComplete()
    }
}

; ==============================================================================
; 7. UI界面刷新与通用辅助工具模块
; ==============================================================================

RefreshUi() {
    global BtnBrowse, BtnChinese, BtnRestore, BtnReset, BtnScan, BtnUpdate, ComboServerList, EditInstallPath
    global g_ConfigCache, g_CurrentServer, g_InstallPath, g_IsPatching, g_IsSyncing, TabCtrl, TextTipInfo, MainGui, BtnRefreshStatus

    if (TabCtrl.Value != 1) {
        TextTipInfo.Opt("+Hidden")
        return
    }

    ShowGameRunningTip := (!g_IsSyncing && IsGameProcessRunning())

    if (ShowGameRunningTip) {
        TextTipInfo.Opt("-Hidden")
        TabCtrl.Move(, , , 470)
        BtnUpdate.Move(177, 428)
        BtnChinese.Move(177, 428)
        BtnRestore.Move(289, 428)
        BtnRefreshStatus.Move(484, 432)
        MainGui.Move(, , , 500 + g_WindowsOffset.h)
    } else {
        TextTipInfo.Opt("+Hidden")
        TabCtrl.Move(, , , 460)
        BtnUpdate.Move(177, 418)
        BtnChinese.Move(177, 418)
        BtnRestore.Move(289, 418)
        BtnRefreshStatus.Move(484, 422)
        MainGui.Move(, , , 490 + g_WindowsOffset.h)
    }

    if (g_IsPatching || g_IsSyncing) {
        BtnUpdate.Opt("+Disabled")
        BtnChinese.Opt("+Disabled")
        BtnRestore.Opt("+Disabled")
        BtnScan.Opt("+Disabled")
        BtnBrowse.Opt("+Disabled")
        BtnReset.Opt("+Disabled")
        ComboServerList.Opt("+Disabled")
        BtnRefreshStatus.Opt("+Disabled")

        return
    }

    ComboServerList.Opt("-Disabled")
    BtnScan.Opt("-Disabled")
    BtnBrowse.Opt("-Disabled")
    BtnRefreshStatus.Opt("-Disabled")

    if (!g_CurrentServer.Has("id"))
        return

    Info := GetLocalPatchInfo()
    IsPatched := Info["isPatched"]
    UpdateBranches := GetPatchUpdates(g_CurrentServer)

    if (UpdateBranches.Length > 0) {
        BtnUpdate.Opt("-Hidden")
        BtnUpdate.Opt("-Disabled")
        BtnChinese.Opt("+Hidden")
    } else {
        BtnUpdate.Opt("+Hidden")
        BtnChinese.Opt("-Hidden")
        BtnChinese.Opt(IsPatched == 1 ? "+Disabled" : "-Disabled")
    }

    BtnRestore.Opt("-Disabled")

    if (EditInstallPath.Value) {
        BtnReset.Opt("-Disabled")
        if (UpdateBranches.Length > 0)
            BtnUpdate.Focus()
        else if (IsPatched != 1)
            BtnChinese.Focus()
        else
            BtnRestore.Focus()
    } else {
        BtnReset.Opt("+Disabled")
        BtnScan.Focus()
    }
}

SetStatusBarText(StatusMessage := "") {
    global MainStatusBar
    static ClearFunc := () => MainStatusBar.SetText("")

    if (StatusMessage != "") {
        MainStatusBar.SetText("`t" . StatusMessage)
        SetTimer(ClearFunc, -2000)
    } else {
        SetTimer(ClearFunc, 0)
        ClearFunc()
    }
}

AddToolTip(Control, Text) {
    static ToolTips := Map()
    static CurrentShowingHwnd := 0

    if (!ToolTips.Count) {
        OnMessage(0x0200, WM_MOUSEMOVE)
    }
    ToolTips[Control.Hwnd] := Text

    WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
        static PrevHwnd := 0
        global MainStatusBar

        if (hwnd != PrevHwnd) {
            PrevHwnd := hwnd

            if (ToolTips.Has(hwnd)) {
                CurrentShowingHwnd := hwnd
                MainStatusBar.SetText("`t" . ToolTips[hwnd])
            }
            else if (CurrentShowingHwnd != 0) {
                CurrentShowingHwnd := 0
                if (IsSet(MainStatusBar)) {
                    SetStatusBarText()
                } else {
                    ToolTip()
                }
            }
        }
    }
}

FormatFileSize(Bytes) {
    NumericBytes := SafeNumber(Bytes, 0)
    if (NumericBytes <= 0)
        return "0 B"
    if (NumericBytes < 1024)
        return NumericBytes . " B"
    else if (NumericBytes < 1048576)
        return Format("{:.2f} KB", NumericBytes / 1024)
    else if (NumericBytes < 1073741824)
        return Format("{:.2f} MB", NumericBytes / 1048576)
    else
        return Format("{:.2f} GB", NumericBytes / 1073741824)
}

WriteFileAtomic(FilePath, TextContent := "") {
    TmpFile := FilePath . ".tmp"
    try {
        if FileExist(TmpFile)
            FileDelete(TmpFile)
        FileObj := FileOpen(TmpFile, "w", "UTF-8-RAW")
        FileObj.Write(TextContent)
        FileObj.Close()
        if FileExist(FilePath)
            FileDelete(FilePath)
        FileMove(TmpFile, FilePath, 1)
        return true
    } catch {
        if FileExist(TmpFile) {
            try FileDelete(TmpFile)
        }
        return false
    }
}

HashFileMd5(FilePath) {
    if (!FileExist(FilePath))
        return ""

    try {
        f := FileOpen(FilePath, "r")
        if (!f)
            return ""

        if (f.Length == 0) {
            f.Close()
            return "d41d8cd98f00b204e9800998ecf8427e"
        }

        hProv := 0
        if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", 1, "UInt", 0xF0000000) {
            f.Close()
            return ""
        }

        hHash := 0
        if !DllCall("Advapi32\CryptCreateHash", "Ptr", hProv, "UInt", 0x8003, "Ptr", 0, "UInt", 0, "Ptr*", &hHash) {
            DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
            f.Close()
            return ""
        }

        BufSize := 1024 * 1024
        ReadBuf := Buffer(BufSize)

        while (!f.AtEOF) {
            BytesRead := f.RawRead(ReadBuf, BufSize)
            if (BytesRead == 0)
                break

            DllCall("Advapi32\CryptHashData", "Ptr", hHash, "Ptr", ReadBuf, "UInt", BytesRead, "UInt", 0)
        }
        f.Close()

        HashLen := 16
        HashBuf := Buffer(HashLen)
        MD5String := ""

        if DllCall("Advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", 2, "Ptr", HashBuf, "UInt*", &HashLen, "UInt", 0) {
            loop HashLen {
                MD5String .= Format("{:02x}", NumGet(HashBuf, A_Index - 1, "UChar"))
            }
        }

        DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)

        return StrLower(MD5String)
    } catch {
        return ""
    }
}

HashStringMd5(Text) {
    if (Text == "")
        return "d41d8cd98f00b204e9800998ecf8427e"

    try {
        ReqSize := StrPut(Text, "UTF-8")
        Buf := Buffer(ReqSize)
        StrPut(Text, Buf, "UTF-8")

        hProv := 0
        if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &hProv, "Ptr", 0, "Ptr", 0, "UInt", 1, "UInt", 0xF0000000)
            return ""

        hHash := 0
        if !DllCall("Advapi32\CryptCreateHash", "Ptr", hProv, "UInt", 0x8003, "Ptr", 0, "UInt", 0, "Ptr*", &hHash) {
            DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)
            return ""
        }

        DllCall("Advapi32\CryptHashData", "Ptr", hHash, "Ptr", ReqSize - 1, "UInt", 0)

        HashLen := 16
        HashBuf := Buffer(HashLen)
        MD5String := ""

        if DllCall("Advapi32\CryptGetHashParam", "Ptr", hHash, "UInt", 2, "Ptr", HashBuf, "UInt*", &HashLen, "UInt", 0) {
            loop HashLen {
                MD5String .= Format("{:02x}", NumGet(HashBuf, A_Index - 1, "UChar"))
            }
        }

        DllCall("Advapi32\CryptDestroyHash", "Ptr", hHash)
        DllCall("Advapi32\CryptReleaseContext", "Ptr", hProv, "UInt", 0)

        return StrLower(MD5String)
    } catch {
        return ""
    }
}

SafeNumber(Val, DefaultVal := 0) {
    return IsNumber(Val) ? Number(Val) : DefaultVal
}

SafeString(Val, DefaultVal := "") {
    return (Val is Primitive) ? String(Val) : DefaultVal
}

SafeGet(Obj, Key, DefaultValue := "") {
    if (Type(Obj) == "Map" || Type(Obj) == "Array") && Obj.Has(Key)
        return Obj[Key]
    return DefaultValue
}

SafeIniRead(Filename, Section, Key, Default := "") {
    if !FileExist(Filename)
        return Default
    try return IniRead(Filename, Section, Key, Default)
    catch
        return Default
}

SafeIniReadSections(Filename) {
    if !FileExist(Filename)
        return ""
    try return IniRead(Filename)
    catch
        return ""
}

SafeIniWrite(Value, Filename, Section, Key) {
    try {
        IniWrite(Value, Filename, Section, Key)
        return true
    } catch {
        return false
    }
}

GetLocalCachePath(Act) {
    global g_PatchesCacheDir
    FileNameOnly := (Type(Act) == "Map") ? SafeString(Act["filename"]) : SafeString(Act)
    FileNameOnly := LTrim(StrReplace(FileNameOnly, "/", "\"), "\")
    return PathUtil.Normalize(A_ScriptDir . "\" . g_PatchesCacheDir . "\" . FileNameOnly)
}

NormalizeServerConfig(ServersArray) {
    SafeList := []
    if (Type(ServersArray) != "Array")
        return SafeList

    for Srv in ServersArray {
        if (Type(Srv) != "Map")
            continue
        SafeSrv := Map(
            "id", SafeNumber(SafeGet(Srv, "id", 1), 1),
            "name", SafeString(SafeGet(Srv, "name", "未知服务器"), "未知服务器"),
            "display", SafeString(SafeGet(Srv, "display", "未知服务器"), "未知服务器"),
            "keywords", SafeGet(Srv, "keywords", [
                "AION"
            ]),
            "patch_branches", []
        )
        Branches := SafeGet(Srv, "patch_branches", [])
        if (Type(Branches) == "Array") {
            for Br in Branches {
                if (Type(Br) != "Map")
                    continue
                SafeBr := Map(
                    "id", SafeNumber(SafeGet(Br, "id", 1), 1),
                    "source", SafeString(SafeGet(Br, "source", "default"), "default"),
                    "latest_patch_version", SafeString(SafeGet(Br, "latest_patch_version", "1.0.0.0"), "1.0.0.0"),
                    "changelog", SafeString(SafeGet(Br, "changelog", "")),
                    "release_timestamp", SafeNumber(SafeGet(Br, "release_timestamp", 0), 0),
                    "actions", []
                )
                Actions := SafeGet(Br, "actions", [])
                if (Type(Actions) == "Array") {
                    for Act in Actions {
                        if (Type(Act) != "Map")
                            continue

                        RemoteFile := SafeString(SafeGet(Act, "remote_filename", ""))

                        SplitPath(RemoteFile, &ExtractedName)
                        FileNameVal := SafeString(SafeGet(Act, "filename", ""))
                        if (FileNameVal == "")
                            FileNameVal := ExtractedName

                        CleanRemoteUrl := StrReplace(RemoteFile, "\", "/")
                        CleanRemoteUrl := RegExReplace(CleanRemoteUrl, "i)^https?://", "")
                        CleanRemoteUrl := LTrim(CleanRemoteUrl, "/")

                        CleanTargetPath := StrReplace(SafeString(SafeGet(Act, "target_relative_path", "")), "/", "\")
                        CleanTargetPath := LTrim(CleanTargetPath, "\")
                        if InStr(CleanTargetPath, "..")
                            continue

                        SafeAct := Map(
                            "type", SafeString(SafeGet(Act, "type", "add"), "add"),
                            "filename", FileNameVal,
                            "remote_filename", CleanRemoteUrl,
                            "target_relative_path", CleanTargetPath,
                            "file_md5", SafeString(SafeGet(Act, "file_md5", "")),
                            "file_size", SafeNumber(SafeGet(Act, "file_size", 0), 0),
                            "hide", SafeGet(Act, "hide", false)
                        )
                        SafeBr["actions"].Push(SafeAct)
                    }
                }
                SafeSrv["patch_branches"].Push(SafeBr)
            }
        }
        SafeList.Push(SafeSrv)
    }
    return SafeList
}

; ==============================================================================
; 8. 弹窗与视图组件模块
; ==============================================================================

ShowAppUpdateDialog(ChangelogText, DownloadUrlMain, DownloadUrlMinor, IsForceUpdate := false, OnCloseCallback := "") {
    global MainGui, g_DialogCallbacks, g_ClientUpdateData

    MsgId := 1001
    UpdateGui := Gui("+Owner" . MainGui.Hwnd, "软件更新提示")
    UpdateGui.SetFont(, "Microsoft YaHei UI")

    LatestVersion := (Type(g_ClientUpdateData) == "Map" && g_ClientUpdateData.Has("latest_client_version"))
        ? "发现新版本 v" . SafeString(g_ClientUpdateData["latest_client_version"]) . "。"
        : "发现新版本。"

    if (IsForceUpdate)
        UpdateGui.Add("Text", "x20 y20 w360", "当前版本过低，必须升级为最新版本才能使用。").SetFont("bold")
    else
        UpdateGui.Add("Text", "x20 y20 w360", LatestVersion)

    UpdateGui.Add("Edit", "x20 y45 w360 h150 ReadOnly", ChangelogText)

    BtnDownloadMinor := UpdateGui.Add("Button", "x280 y225 w100 h30", "Github 下载")
    BtnDownloadMain := UpdateGui.Add("Button", "x168 y225 w100 h30 Default", "主线路下载")
    BtnDownloadMain.Focus()

    BtnDownloadMain.OnEvent("Click", (*) => (DownloadUrlMain != "" ? Run(DownloadUrlMain) : false))
    BtnDownloadMinor.OnEvent("Click", (*) => (DownloadUrlMinor != "" ? Run(DownloadUrlMinor) : false))

    CloseDialog(Result := 0) {
        MainGui.Opt("-Disabled")
        UpdateGui.Destroy()
        if (IsForceUpdate)
            ExitApp()
        else
            RefreshUi()

        if (OnCloseCallback)
            OnCloseCallback()
    }

    g_DialogCallbacks[MsgId] := CloseDialog

    UpdateGui.OnEvent("Close", (*) => PostMessage(0x0900, MsgId, 0, , MainGui.Hwnd))
    UpdateGui.OnEvent("Escape", (*) => PostMessage(0x0900, MsgId, 0, , MainGui.Hwnd))

    MainGui.Opt("+Disabled")
    UpdateGui.Show("w400 h275")
    BtnDownloadMain.Focus()
}

ShowBulletinDialog(ContentText, BulletinVersion, OnCloseCallback := "") {
    global MainGui, g_LastSeenBulletinVersion, g_DialogCallbacks

    MsgId := 1002
    BulletinGui := Gui("+Owner" . MainGui.Hwnd, "最新公告")
    BulletinGui.SetFont(, "Microsoft YaHei UI")

    BulletinGui.Add("Edit", "x20 y20 w360 h150 ReadOnly -WantReturn", ContentText)

    BtnConfirm := BulletinGui.Add("Button", "x280 y200 w100 h30 Default", "我知道了")
    BtnConfirm.Focus()

    CloseDialog(*) {
        g_LastSeenBulletinVersion := BulletinVersion
        SaveAllConfig()
        MainGui.Opt("-Disabled")
        BulletinGui.Destroy()
        RefreshUi()

        if (OnCloseCallback)
            OnCloseCallback()
    }

    g_DialogCallbacks[MsgId] := CloseDialog

    BtnConfirm.OnEvent("Click", (*) => PostMessage(0x0900, MsgId, 1, , MainGui.Hwnd))
    BulletinGui.OnEvent("Close", (*) => PostMessage(0x0900, MsgId, 0, , MainGui.Hwnd))

    MainGui.Opt("+Disabled")
    BulletinGui.Show("w400 h250")
}

ShowConfirmDialog(Text, Callback := "") {
    global MainGui, g_DialogCallbacks

    MsgId := 1003
    ConfirmGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    ConfirmGui.SetFont(, "Microsoft YaHei UI")

    ConfirmGui.Add("Text", "x20 y20 w310 h60", Text)

    BtnCancel := ConfirmGui.Add("Button", "x246 y102 w84 h30", "取消")
    BtnConfirm := ConfirmGui.Add("Button", "x134 y102 w100 h30 Default", "确认")
    BtnConfirm.Focus()

    CloseDialog(UserChoice) {
        MainGui.Opt("-Disabled")
        ConfirmGui.Destroy()
        RefreshUi()
        if (Callback)
            Callback(UserChoice)
    }

    g_DialogCallbacks[MsgId] := CloseDialog

    BtnConfirm.OnEvent("Click", (*) => PostMessage(0x0900, MsgId, 1, , MainGui.Hwnd))
    BtnCancel.OnEvent("Click", (*) => PostMessage(0x0900, MsgId, 0, , MainGui.Hwnd))
    ConfirmGui.OnEvent("Close", (*) => PostMessage(0x0900, MsgId, 0, , MainGui.Hwnd))

    MainGui.Opt("+Disabled")
    ConfirmGui.Show("w350 h150")
}

ShowMessageDialog(Text, Callback := "") {
    global MainGui, g_DialogCallbacks

    MsgId := 1004
    MessageGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    MessageGui.SetFont(, "Microsoft YaHei UI")

    MessageGui.Add("Text", "x20 y20 w310 h60", Text)

    BtnConfirm := MessageGui.Add("Button", "x230 y102 w100 h30 Default", "确认")
    BtnConfirm.Focus()

    CloseDialog(*) {
        MainGui.Opt("-Disabled")
        MessageGui.Destroy()
        RefreshUi()
        if (Callback)
            Callback()
    }

    g_DialogCallbacks[MsgId] := CloseDialog

    BtnConfirm.OnEvent("Click", (*) => PostMessage(0x0900, MsgId, 1, , MainGui.Hwnd))
    MessageGui.OnEvent("Close", (*) => PostMessage(0x0900, MsgId, 0, , MainGui.Hwnd))

    MainGui.Opt("+Disabled")
    MessageGui.Show("w350 h150")
}

ShowMultiBranchDialog(Branches, Callback := "", IsUpdateList := false) {
    global g_CurrentServer, MainGui

    DlgTitle := IsUpdateList ? "选择汉化补丁来源" : "选择汉化补丁来源"
    ChoiceGui := Gui("+Owner" . MainGui.Hwnd, DlgTitle)
    ChoiceGui.SetFont(, "Microsoft YaHei UI")

    TipText := IsUpdateList ? "当前汉化补丁有更新。" : ("选择 AION2 " . g_CurrentServer["name"] . " 汉化补丁来源，不同来源游戏内翻译完成度可能不同。")
    ChoiceGui.Add("Text", "x20 y15 w410 h25", TipText).SetFont("bold")

    VerHeaderTitle := IsUpdateList ? "版本信息" : "版本信息"
    LV := ChoiceGui.Add("ListView", "x20 y45 w410 h140 -Multi", [
        "来源",
        VerHeaderTitle,
        "补丁大小",
        "更新时间"
    ])
    LV_ApplyExplorerTheme(LV)
    LV.Opt("-Redraw")

    for Index, Item in Branches {
        BranchObj := IsUpdateList ? Item.Branch : Item

        TsVal := SafeGet(BranchObj, "release_timestamp", 0)
        ReleaseTime := "未知"
        if (IsNumber(TsVal) && TsVal > 0) {
            try {
                ReleaseTime := FormatTime(DateAdd("19700101000000", TsVal + DateDiff(A_Now, A_NowUTC, "Seconds"), "Seconds"), "yyyy-MM-dd HH:mm:ss")
            }
        }

        if (IsUpdateList) {
            VerStr := Item.LocalVersion . " -> " . Item.LatestVersion
        } else {
            VerStr := BranchObj.Has("latest_patch_version") ? SafeString(BranchObj["latest_patch_version"]) : "1.0.0.0"
        }

        Src := BranchObj.Has("source") ? SafeString(BranchObj["source"]) : "default"

        TotalSize := 0
        if (BranchObj.Has("actions") && Type(BranchObj["actions"]) == "Array") {
            for Act in BranchObj["actions"] {
                ActType := Act.Has("type") ? Act["type"] : "add"
                if (ActType == "add" || ActType == "replace" || ActType == "run") {
                    TotalSize += SafeNumber(SafeGet(Act, "file_size", 0), 0)
                }
            }
        }
        PatchSizeStr := FormatFileSize(TotalSize)

        RowNumber := LV.Add("", Src, VerStr, PatchSizeStr, ReleaseTime)
        LV_SetItemLParam(LV.Hwnd, RowNumber, Index)
    }

    LV.ModifyCol(1, "AutoHdr")
    LV.ModifyCol(2, "AutoHdr")
    LV.ModifyCol(3, "AutoHdr")
    LV.ModifyCol(4, "AutoHdr")
    LV.Opt("+Redraw")

    ConfirmBtnText := IsUpdateList ? "确认更新" : "确认"
    BtnCancel := ChoiceGui.Add("Button", "x346 y200 w84 h30", "取消")
    BtnConfirm := ChoiceGui.Add("Button", "x234 y200 w100 h30 +Disabled", ConfirmBtnText)

    LV.OnEvent("ItemSelect", (Ctrl, Item, Selected) => BtnConfirm.Opt(LV.GetNext(0) > 0 ? "-Disabled" : "+Disabled"))
    BtnConfirm.OnEvent("Click", (*) => HandleSubmit(1))
    BtnCancel.OnEvent("Click", (*) => HandleSubmit(0))
    ChoiceGui.OnEvent("Close", (*) => HandleSubmit(0))

    sortState := {
        col: 0,
        desc: false
    }
    LV.OnEvent("ColClick", SortListView.Bind(sortState))

    SortListView(state, Ctrl, Column) {
        if (state.col == Column) {
            state.desc := !state.desc
        } else {
            state.col := Column
            state.desc := false
        }
        try {
            if (state.desc) {
                Ctrl.ModifyCol(Column, "SortDesc")
            } else {
                Ctrl.ModifyCol(Column, "Sort")
            }
            LV_SetHeaderSortArrow(Ctrl, Column, state.desc)
        }
    }

    HandleSubmit(IsConfirmed) {
        if (IsConfirmed && !BtnConfirm.Enabled)
            return

        SelectedBranch := ""
        if (IsConfirmed == 1) {
            RowNumber := LV.GetNext(0)
            if (RowNumber) {
                RealIdx := LV_GetItemLParam(LV.Hwnd, RowNumber)
                if (RealIdx > 0 && RealIdx <= Branches.Length)
                    SelectedBranch := IsUpdateList ? Branches[RealIdx].Branch : Branches[RealIdx]
            }
        }

        MainGui.Opt("-Disabled")
        ChoiceGui.Destroy()
        RefreshUi()

        if (Callback)
            Callback(SelectedBranch)
    }

    MainGui.Opt("+Disabled")
    ChoiceGui.Show("w450 h250")

    if (IsUpdateList && Branches.Length > 0) {
        LV.Modify(1, "Select Focus")
        SelectedBranch := Branches[1]
        BtnConfirm.Enabled := true
    } else {
        LV.Modify(0, "-Select")
        SelectedBranch := ""
        BtnConfirm.Enabled := false
    }
}

ShowMultiPathDialog(ValidGames, Callback := "") {
    global g_CurrentServer, MainGui

    ChoiceGui := Gui("+Owner" . MainGui.Hwnd, "选择游戏目录")
    ChoiceGui.SetFont(, "Microsoft YaHei UI")
    ChoiceGui.Add("Text", "x20 y15 w410 h25", "选择 AION2 " . g_CurrentServer["name"] . "安装目录：")

    LV := ChoiceGui.Add("ListView", "x20 y45 w410 h140 -Multi", [
        "名称",
        "安装目录"
    ])
    LV_ApplyExplorerTheme(LV)
    LV.Opt("-Redraw")

    for Index, Game in ValidGames {
        RowNumber := LV.Add("", Game.SoftwareDisplayName, Game.GameInstallPath)
        LV_SetItemLParam(LV.Hwnd, RowNumber, Index)
    }

    LV.ModifyCol(1, "AutoHdr")
    LV.ModifyCol(2, "AutoHdr")
    LV.Opt("+Redraw")

    BtnCancel := ChoiceGui.Add("Button", "x346 y200 w84 h30", "取消")
    BtnConfirm := ChoiceGui.Add("Button", "x234 y200 w100 h30 +Disabled", "确认")

    LV.OnEvent("ItemSelect", (Ctrl, Item, Selected) => BtnConfirm.Opt(LV.GetNext(0) > 0 ? "-Disabled" : "+Disabled"))
    BtnConfirm.OnEvent("Click", (*) => HandleSubmit(1))
    BtnCancel.OnEvent("Click", (*) => HandleSubmit(0))
    ChoiceGui.OnEvent("Close", (*) => HandleSubmit(0))

    sortState := {
        col: 0,
        desc: false
    }
    LV.OnEvent("ColClick", SortListView.Bind(sortState))

    SortListView(state, Ctrl, Column) {
        if (state.col == Column) {
            state.desc := !state.desc
        } else {
            state.col := Column
            state.desc := false
        }
        try {
            if (state.desc) {
                Ctrl.ModifyCol(Column, "SortDesc")
            } else {
                Ctrl.ModifyCol(Column, "Sort")
            }
            LV_SetHeaderSortArrow(Ctrl, Column, state.desc)
        }
    }

    HandleSubmit(IsConfirmed) {
        if (IsConfirmed && !BtnConfirm.Enabled)
            return

        UserChoicePath := ""
        if (IsConfirmed == 1) {
            RowNumber := LV.GetNext(0)
            if (RowNumber) {
                RealIdx := LV_GetItemLParam(LV.Hwnd, RowNumber)
                if (RealIdx > 0 && RealIdx <= ValidGames.Length)
                    UserChoicePath := ValidGames[RealIdx].GameInstallPath
            }
        }

        MainGui.Opt("-Disabled")
        ChoiceGui.Destroy()
        RefreshUi()

        if (Callback)
            Callback(UserChoicePath)
    }

    MainGui.Opt("+Disabled")
    ChoiceGui.Show("w450 h250")
    LV.Modify(0, "-Select")
}

LV_SetItemLParam(lv, row, param) {
    static LVM_SETITEMW := 0x104C
    static LVIF_PARAM := 0x0004

    lvitem := Buffer(A_PtrSize == 8 ? 48 : 36, 0)
    NumPut("UInt", LVIF_PARAM, lvitem, 0)
    NumPut("Int", row - 1, lvitem, 4)

    offset_lparam := A_PtrSize == 8 ? 40 : 32
    NumPut("Ptr", Integer(param), lvitem, offset_lparam)

    return SendMessage(LVM_SETITEMW, 0, lvitem.Ptr, lv)
}

LV_GetItemLParam(lv, row) {
    static LVM_GETITEMW := 0x104B
    static LVIF_PARAM := 0x0004

    lvitem := Buffer(A_PtrSize == 8 ? 48 : 36, 0)
    NumPut("UInt", LVIF_PARAM, lvitem, 0)
    NumPut("Int", row - 1, lvitem, 4)

    SendMessage(LVM_GETITEMW, 0, lvitem.Ptr, lv)

    offset_lparam := A_PtrSize == 8 ? 40 : 32
    return NumGet(lvitem, offset_lparam, "Ptr")
}

LV_ApplyExplorerTheme(LV) {
    try DllCall("uxtheme\SetWindowTheme", "ptr", LV.Hwnd, "str", "Explorer", "ptr", 0)

    exStyle := SendMessage(LVM_GETEXTENDEDLISTVIEWSTYLE, 0, 0, LV)
    exStyle |= LVS_EX_FULLROWSELECT
    exStyle |= LVS_EX_DOUBLEBUFFER
    exStyle |= LVS_EX_HEADERDRAGDROP
    exStyle |= LVS_EX_INFOTIP
    exStyle |= LVS_EX_LABELTIP

    SendMessage(LVM_SETEXTENDEDLISTVIEWSTYLE, 0, exStyle, LV)
}

LV_SetHeaderSortArrow(LV, sort_col, desc := false) {
    hHeader := SendMessage(LVM_GETHEADER, 0, 0, LV)
    if !hHeader
        return

    hdi_size := (A_PtrSize == 8) ? 72 : 48
    fmt_offset := (A_PtrSize == 8) ? 28 : 20
    hdi := Buffer(hdi_size, 0)
    col_count := LV.GetCount("Col")

    loop col_count {
        col_index0 := A_Index - 1

        NumPut("UInt", HDI_FORMAT, hdi, 0)
        ok := DllCall("SendMessage", "ptr", hHeader, "uint", HDM_GETITEM, "ptr", col_index0, "ptr", hdi.Ptr, "ptr")
        if !ok
            continue

        fmt := NumGet(hdi, fmt_offset, "Int")
        fmt &= ~HDF_SORTUP
        fmt &= ~HDF_SORTDOWN

        if (A_Index == sort_col)
            fmt |= desc ? HDF_SORTDOWN : HDF_SORTUP

        NumPut("UInt", HDI_FORMAT, hdi, 0)
        NumPut("Int", fmt, hdi, fmt_offset)

        DllCall("SendMessage", "ptr", hHeader, "uint", HDM_SETITEM, "ptr", col_index0, "ptr", hdi.Ptr, "ptr")
    }
}

LoadEmbeddedPictureHandle(RelativePath) {
    static BitmapCacheMap := Map()

    NormalizedPath := PathUtil.Normalize(A_ScriptDir . "\" . RelativePath)
    if (BitmapCacheMap.Has(NormalizedPath)) {
        return BitmapCacheMap[NormalizedPath]
    }

    try {
        TempFilePath := PathUtil.Normalize(A_Temp . "\" . A_TickCount . "_" . Random(1000, 9999) . ".tmp")
        if InStr(NormalizedPath, "GuGuai.png") {
            FileInstall("AutoHotkey\GuGuai.png", TempFilePath, 1)
        } else if InStr(NormalizedPath, "AK.png") {
            FileInstall("AutoHotkey\AK.png", TempFilePath, 1)
        } else if InStr(NormalizedPath, "XaoYao.png") {
            FileInstall("AutoHotkey\XaoYao.png", TempFilePath, 1)
        } else if FileExist(NormalizedPath) {
            FileCopy(NormalizedPath, TempFilePath, 1)
        } else {
            return 0
        }

        hBitmap := LoadPicture(TempFilePath)
        try FileDelete(TempFilePath)

        if (hBitmap) {
            BitmapCacheMap[NormalizedPath] := hBitmap
            return hBitmap
        }
    } catch {
        return 0
    }
    return 0
}

CreateCardControl(GuiObj, OptionsMap) {
    global g_CursorHwndMap

    PosX := OptionsMap.HasProp("x") ? OptionsMap.x : 15
    PosY := OptionsMap.HasProp("y") ? OptionsMap.y : 15
    IconRes := OptionsMap.HasProp("icon") ? OptionsMap.icon : "🚀"
    TitleText := OptionsMap.HasProp("title") ? OptionsMap.title : "默认标题"
    DescText := OptionsMap.HasProp("desc") ? OptionsMap.desc : "默认描述…"
    TargetUrl := OptionsMap.HasProp("url") ? OptionsMap.url : ""
    CardWidth := OptionsMap.HasProp("width") ? OptionsMap.width : 536
    CardHeight := OptionsMap.HasProp("height") ? OptionsMap.height : 75
    ShowBorder := OptionsMap.HasProp("border") ? OptionsMap.border : true
    ClickHandler := (*) => (TargetUrl != "" ? Run(TargetUrl) : false)
    if (ShowBorder) {
        GuiObj.Add("GroupBox", Format("x{} y{} w{} h{}", PosX, PosY, CardWidth, CardHeight))
    }
    if (StrLen(IconRes) <= 4) {
        IconCtrl := GuiObj.Add("Text", Format("x{} y{} w48 h48 +0x100 +0x200 Center BackgroundTrans", PosX + 15, PosY +
            18), IconRes).SetFont("s20", "Segoe UI Emoji")
    } else {
        hBitmap := LoadEmbeddedPictureHandle(IconRes)
        if (hBitmap != 0) {
            IconCtrl := GuiObj.Add("Picture", Format("x{} y{} w48 h48 +0x100 BackgroundTrans", PosX + 15, PosY + 18),
                "HBITMAP:*" . hBitmap)
        } else {
            IconCtrl := GuiObj.Add("Text", Format("x{} y{} w48 h48 +0x100 +0x200 Center BackgroundTrans", PosX + 15,
                PosY + 18), "❌").SetFont("s12", "Microsoft YaHei")
        }
    }

    IconCtrl.OnEvent("Click", ClickHandler)
    g_CursorHwndMap[IconCtrl.Hwnd] := true
    TextX := PosX + 75
    TextW := CardWidth - 85

    GuiObj.Add("Text", Format("x{} y{} w{} c333333 BackgroundTrans", TextX, PosY + 15, TextW), TitleText).SetFont(
        "s10 bold", "Microsoft YaHei")
    GuiObj.Add("Text", Format("x{} y{} w{} c666666 BackgroundTrans", TextX, PosY + 38, TextW), DescText).SetFont(
        "s9 norm", "Microsoft YaHei")
    MaskX := PosX + 2
    MaskY := PosY + 2
    MaskW := CardWidth - 4
    MaskH := CardHeight - 4

    ClickMaskCtrl := GuiObj.Add("Text", Format("x{} y{} w{} h{} +0x100 BackgroundTrans", MaskX, MaskY, MaskW, MaskH),
        "")
    ClickMaskCtrl.OnEvent("Click", ClickHandler)
    g_CursorHwndMap[ClickMaskCtrl.Hwnd] := true
}

OnMessage(0x0900, HandleDialogEvent)
OnMessage(0x0020, WM_SETCURSOR)

HandleDialogEvent(wParam, lParam, msg, hwnd) {
    if (g_DialogCallbacks.Has(wParam)) {
        CallbackFunc := g_DialogCallbacks[wParam]
        g_DialogCallbacks.Delete(wParam)
        CallbackFunc(lParam)
    }
}

WM_SETCURSOR(wParam, lParam, msg, hwnd) {
    global g_CursorHwndMap
    static hHandCursor := 0
    if (g_CursorHwndMap.Has(wParam) && g_CursorHwndMap[wParam]) {
        if (!hHandCursor) {
            hHandCursor := DllCall("LoadCursor", "ptr", 0, "int", 32649, "ptr")
        }
        DllCall("SetCursor", "ptr", hHandCursor)
        return true
    }
}


GetWindowFrameOffset(GuiObj) {

    rectWindow := Buffer(16, 0)
    rectClient := Buffer(16, 0)


    DllCall("GetWindowRect", "ptr", GuiObj.Hwnd, "ptr", rectWindow)

    DllCall("GetClientRect", "ptr", GuiObj.Hwnd, "ptr", rectClient)

    winWidth := NumGet(rectWindow, 8, "Int") - NumGet(rectWindow, 0, "Int")
    winHeight := NumGet(rectWindow, 12, "Int") - NumGet(rectWindow, 4, "Int")

    clientWidth := NumGet(rectClient, 8, "Int") - NumGet(rectClient, 0, "Int")
    clientHeight := NumGet(rectClient, 12, "Int") - NumGet(rectClient, 4, "Int")


    offsetW := winWidth - clientWidth
    offsetH := winHeight - clientHeight

    return {
        w: offsetW,
        h: offsetH
    }
}
