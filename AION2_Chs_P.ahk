;@Ahk2Exe-SetName AION2_Chs Patch
;@Ahk2Exe-SetOrigFilename AION2_Chs_P.exe
;@Ahk2Exe-SetProductName AION2 Chs Patch
;@Ahk2Exe-SetDescription AION2 一键汉化工具
;@Ahk2Exe-SetVersion 1.2.0.0
;@Ahk2Exe-SetCopyright Copyright © 2026
;@Ahk2Exe-SetMainIcon AutoHotkey\icon.ico

#Include ".\AutoHotkey\lib\UniqueInstance.ahk"
#Include ".\AutoHotkey\lib\PathUtil.ahk"
#Include ".\AutoHotkey\Lib\WinHttpRequest.ahk"
#Include ".\AutoHotkey\lib\JSON.ahk"

;@format array_style: expand, object_style: expand

#NoTrayIcon
Persistent true
#SingleInstance Off

UiResult := UniqueInstance.Ensure(Map(
    "preferRunAsAdmin", true,
    "allowCoexist", true,
    "showReport", true
))

global g_CurrentAppVersion := "1.2.0.0"
global g_ConfigFile := "config.ini"
global g_AppManifestFilename := "app_manifest.json"
global g_PatchManifestFilename := "patch_manifest.json"
global g_PatchsCacheDir := "data"

global g_DefaultPreUrl := "https://raw.githubusercontent.com/nanhezzb/Aion2-Chinese-Patch/refs/heads/main"
global g_DefaultProxyMirrors := [
    "https://gh-proxy.com",
    "https://gh.ddlc.top"
]

global g_GlobalConfigData := Map()
global g_ClientUpdateData := Map()
global g_ServersConfigData := []
global g_CloudBulletinData := Map()

global g_IsDialogShowing := false
global g_IsLocalInitComplete := false
global g_InstallPath := ""
global g_LastSeenBulletinVersion := "1.1.0.0"
global g_RequestTimeoutSeconds := 30
global g_CleanPreUrl := RTrim(g_DefaultPreUrl, "/")
global g_CleanProxyMirrors := []
global g_CleanRemoteAppUrl := ""
global g_CleanRemotePatchUrl := ""
global g_BestDownloadPrefix := ""
global g_BestLatency := 99999
global g_CurrentServer := Map()
global g_ConfigCache := {
    Settings: {
        LastServerID: 102
    }
}

; ==============================================================================
; 安全获取对象键值
; ==============================================================================
SafeGet(Obj, Key, DefaultValue := "") {
    if (Type(Obj) == "Map" || Type(Obj) == "Array") && Obj.Has(Key)
        return Obj[Key]
    return DefaultValue
}

; ==============================================================================
; 安全读取 INI 配置文件
; ==============================================================================
SafeIniRead(Filename, Section, Key, Default := "") {
    try return IniRead(Filename, Section, Key, Default)
    catch
        return Default
}

; ==============================================================================
; 规范化服务器配置数据结构
; ==============================================================================
GetLocalCachePath(RemoteFilename) {
    global g_PatchsCacheDir
    CleanRelPath := StrReplace(RemoteFilename, "/", "\")
    CleanRelPath := LTrim(CleanRelPath, "\")
    SplitPath(CleanRelPath, &FileNameOnly)
    return PathUtil.Normalize(A_ScriptDir . "\" . g_PatchsCacheDir . "\" . FileNameOnly)
}
NormalizeServerConfig(ServersArray) {
    SafeList := []
    if (Type(ServersArray) != "Array")
        return SafeList

    for Srv in ServersArray {
        if (Type(Srv) != "Map")
            continue
        SafeSrv := Map(
            "id", SafeGet(Srv, "id", 1),
            "name", SafeGet(Srv, "name", "未知服务器"),
            "display", SafeGet(Srv, "display", "未知服务器"),
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
                    "id", SafeGet(Br, "id", 1),
                    "source", SafeGet(Br, "source", "default"),
                    "latest_patch_version", SafeGet(Br, "latest_patch_version", "1.0.0.0"),
                    "changelog", SafeGet(Br, "changelog", ""),
                    "release_timestamp", SafeGet(Br, "release_timestamp", 0),
                    "actions", []
                )
                Actions := SafeGet(Br, "actions", [])
                if (Type(Actions) == "Array") {
                    for Act in Actions {
                        if (Type(Act) != "Map")
                            continue
                        SafeAct := Map(
                            "type", SafeGet(Act, "type", "add"),
                            "remote_filename", SafeGet(Act, "remote_filename", ""),
                            "target_relative_path", SafeGet(Act, "target_relative_path", ""),
                            "file_md5", SafeGet(Act, "file_md5", ""),
                            "file_size", Number(SafeGet(Act, "file_size", 0))
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

global g_DefaultServers := NormalizeServerConfig([
    Map(
        "id", 102, "name", "台服", "display", "台服 - PURPLE", "keywords", [
            "AION"
        ],
        "patch_branches", [
            Map("id", 1, "source", "xy", "latest_patch_version", "1.0.0.0", "actions", [
                Map(
                    "type", "add", "remote_filename", "patchs/xy_pakchunk504000-Windows_9999_P.pak",
                    "target_relative_path", "Aion2\Content\Paks\L10N\Text\zh-TW\pakchunk504000-Windows_9999_P.pak",
                    "file_md5", "d8f909cef6c96595e0e3514ed0e744da", "file_size", 3672850
                )
            ])
        ]
    )
])

global MainGui := Gui(, "AION2 一键汉化工具 1.2")
MainGui.SetFont("s9", "Microsoft YaHei")

global TabCtrl := MainGui.AddTab3("x-1 y10 w574 h460", [
    "中文汉化",
    "免费加速器"
])

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

TabCtrl.UseTab(2)
MainGui.AddLink("x31 y75 w510 r1", '<a href="https://www.ggkuai.com/">古怪加速器 - 每天0-16点免费，极速稳定全球网游加速。</a>')
MainGui.AddLink("x31 y100 w510 r1",
    '<a href="https://www.akspeedy.com/html/invite_new/invite_download.html?inviter=3Xtkus4t">AK加速器- 每天0-14点免费，支持全球网游加速。</a>'
)
MainGui.AddLink("x31 y125 w510 r1",
    '<a href="https://www.xiaoyao.co/index.htm">逍遥加速器 - 24小时免费加速，全新模式 - 平台加速。支持 Steam、EA、Epic、暴雪等平台。</a>')

TabCtrl.UseTab(0)
global MainStatusBar := MainGui.AddStatusBar(, "")

ComboServerList.OnEvent("Change", (*) => SelectServer())
BtnScan.OnEvent("Click", (*) => OnScanButtonClick())
BtnBrowse.OnEvent("Click", BrowseFolder)
BtnReset.OnEvent("Click", DoResetConfig)
BtnChinese.OnEvent("Click", DoChinesePatch)
BtnRestore.OnEvent("Click", DoRestorePatch)
MainGui.OnEvent("Close", (*) => ExitApp())

g_ServersConfigData := g_DefaultServers
InitProxyMirrors(g_DefaultProxyMirrors)
InitializeApp()

; ==============================================================================
; 初始化应用程序环境
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

; ==============================================================================
; 解析并应用配置清单 (Manifest)
; ==============================================================================
ParseAndApplyManifest(JsonContent, IsPatchFile := false) {
    global g_ClientUpdateData, g_ServersConfigData, g_CloudBulletinData, g_GlobalConfigData

    try {
        Parsed := JSON.parse(JsonContent)
        if (Type(Parsed) != "Map")
            return false

        if (Parsed.Has("client_update"))
            g_ClientUpdateData := Parsed["client_update"]

        if (IsPatchFile && Parsed.Has("servers_config"))
            g_ServersConfigData := NormalizeServerConfig(Parsed["servers_config"])

        if (IsPatchFile && Parsed.Has("cloud_bulletin"))
            g_CloudBulletinData := Parsed["cloud_bulletin"]

        if (Parsed.Has("global_config") && Type(Parsed["global_config"]) == "Map") {
            g_GlobalConfigData := Parsed["global_config"]
            g_RequestTimeoutSeconds := Number(SafeGet(g_GlobalConfigData, "download_timeout_seconds", 30))
            InitProxyMirrors(SafeGet(g_GlobalConfigData, "proxy_mirrors", g_DefaultProxyMirrors))
        }
        return true
    } catch {
        return false
    }
}

; ==============================================================================
; 加载本地清单文件
; ==============================================================================
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

; ==============================================================================
; 启动后台云端同步
; ==============================================================================
StartCloudSync() {
    global g_ConfigFile, g_RequestTimeoutSeconds, g_IsLocalInitComplete, g_IsDialogShowing, g_CloudBulletinData,
        g_ClientUpdateData

    if (!g_IsLocalInitComplete)
        return

    ShowStatus("正在后台拉取云端最新配置...")
    IsSyncSuccess := SyncCloudConfig()

    if (IsSyncSuccess) {
        IniWrite(DateDiff(A_NowUTC, "19700101000000", "Seconds"), g_ConfigFile, "Settings", "LastCheckTime")
        IniWrite(g_RequestTimeoutSeconds, g_ConfigFile, "Settings", "RequestTimeoutSeconds")
        if (!g_IsDialogShowing) {
            SafeRefreshUi()
            ShowStatus("云端配置同步成功，已保存至本地。")
        } else {
            ShowStatus("云端配置同步成功，等待重启动生效。")
        }
    } else {
        ShowStatus("连接超时或离线，已加载本地配置文件。")
    }

    if (Type(g_ClientUpdateData) == "Map" && g_ClientUpdateData.Count > 0)
        CheckAppUpdate(g_ClientUpdateData)

    if (Type(g_CloudBulletinData) == "Map" && g_CloudBulletinData.Count > 0)
        CheckBulletin(g_CloudBulletinData)
}

; ==============================================================================
; 同步云端配置文件
; ==============================================================================
SyncCloudConfig() {
    global g_AppManifestFilename, g_PatchManifestFilename, g_RequestTimeoutSeconds, g_CleanRemoteAppUrl,
        g_CleanRemotePatchUrl

    IsAppSuccess := false
    IsPatchSuccess := false

    if (AppJson := HttpGetText(g_CleanRemoteAppUrl, g_RequestTimeoutSeconds)) {
        if (ParseAndApplyManifest(AppJson, false)) {
            WriteFileAtomic(g_AppManifestFilename, AppJson)
            IsAppSuccess := true
        }
    }

    if (PatchJson := HttpGetText(g_CleanRemotePatchUrl, g_RequestTimeoutSeconds)) {
        if (ParseAndApplyManifest(PatchJson, true)) {
            WriteFileAtomic(g_PatchManifestFilename, PatchJson)
            IsPatchSuccess := true
        }
    }

    return (IsAppSuccess || IsPatchSuccess)
}

; ==============================================================================
; 初始化代理镜像列表
; ==============================================================================
InitProxyMirrors(MirrorsArray) {
    global g_CleanProxyMirrors := []
    if (Type(MirrorsArray) == "Array") {
        for Mirror in MirrorsArray {
            if (Mirror != "")
                g_CleanProxyMirrors.Push(RTrim(Mirror, "/"))
        }
    }
}

; ==============================================================================
; 更新全局远程请求链接
; ==============================================================================
UpdateGlobalUrls() {
    global g_CleanPreUrl, g_AppManifestFilename, g_PatchManifestFilename, g_CleanRemoteAppUrl, g_CleanRemotePatchUrl
    TimestampParam := "?t=" . DateDiff(A_NowUTC, "19700101000000", "Seconds")
    g_CleanRemoteAppUrl := g_CleanPreUrl . "/" . g_AppManifestFilename . TimestampParam
    g_CleanRemotePatchUrl := g_CleanPreUrl . "/" . g_PatchManifestFilename . TimestampParam
}

; ==============================================================================
; 读取本地 INI 配置信息
; ==============================================================================
ReadConfig() {
    global g_ConfigCache, g_ConfigFile, g_ServersConfigData, g_LastSeenBulletinVersion
    g_LastSeenBulletinVersion := SafeIniRead(g_ConfigFile, "Settings", "LastSeenBulletinVersion", "1.0.0.0")

    for Server in g_ServersConfigData {
        Sec := "Server_" . Server["id"]
        g_ConfigCache.%Sec% := {
            InstallPath: SafeIniRead(g_ConfigFile, Sec, "install_path", ""),
            IsManualReset: Number(SafeIniRead(g_ConfigFile, Sec, "is_manual_reset", 0)),
            IsPatched: Number(SafeIniRead(g_ConfigFile, Sec, "is_patched", 0)),
            LocalPatchVersion: SafeIniRead(g_ConfigFile, Sec, "local_patch_version", ""),
            LocalPatchBranchID: Number(SafeIniRead(g_ConfigFile, Sec, "local_patch_branch_id", 0))
        }
    }
    RefreshServerComboBox()
}

; ==============================================================================
; 保存所有配置到 INI 文件
; ==============================================================================
SaveAllConfig() {
    global g_ConfigCache, g_ConfigFile, g_ServersConfigData, g_LastSeenBulletinVersion
    IniWrite(g_ConfigCache.Settings.LastServerID, g_ConfigFile, "Settings", "LastServerID")
    IniWrite(g_LastSeenBulletinVersion, g_ConfigFile, "Settings", "LastSeenBulletinVersion")
    for Server in g_ServersConfigData {
        Sec := "Server_" . Server["id"]
        if (g_ConfigCache.HasOwnProp(Sec)) {
            IniWrite(g_ConfigCache.%Sec%.InstallPath, g_ConfigFile, Sec, "install_path")
            IniWrite(g_ConfigCache.%Sec%.IsManualReset, g_ConfigFile, Sec, "is_manual_reset")
            IniWrite(g_ConfigCache.%Sec%.IsPatched, g_ConfigFile, Sec, "is_patched")
            IniWrite(g_ConfigCache.%Sec%.LocalPatchVersion, g_ConfigFile, Sec, "local_patch_version")
            IniWrite(g_ConfigCache.%Sec%.LocalPatchBranchID, g_ConfigFile, Sec, "local_patch_branch_id")
        }
    }
}

; ==============================================================================
; 刷新服务器下拉列表控件
; ==============================================================================
RefreshServerComboBox() {
    global g_ServersConfigData, ComboServerList, g_ConfigFile, g_CurrentServer, g_ConfigCache

    DropDownOptions := []
    SavedLastId := Number(SafeIniRead(g_ConfigFile, "Settings", "LastServerID", 102))
    TargetIndex := 1

    loop g_ServersConfigData.Length {
        Server := g_ServersConfigData[A_Index]
        DropDownOptions.Push(Server["display"])
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

; ==============================================================================
; 刷新当前选中的服务器业务数据
; ==============================================================================
RefreshServerData() {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath

    if (!g_CurrentServer.Has("id"))
        return

    Sec := "Server_" . g_CurrentServer["id"]
    UpdateNoticeText()

    if (!g_ConfigCache.HasOwnProp(Sec)) {
        g_ConfigCache.%Sec% := {
            InstallPath: "",
            IsManualReset: 0,
            IsPatched: 0,
            LocalPatchVersion: "",
            LocalPatchBranchID: 0
        }
    }

    SavedPath := g_ConfigCache.%Sec%.InstallPath
    if (SavedPath != "") {
        if (DirExist(SavedPath) && FileExist(SavedPath . "\Aion2\Binaries\Win64\Aion2.exe")) {
            g_InstallPath := SavedPath
            EditInstallPath.Value := SavedPath
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

; ==============================================================================
; 刷新界面控件状态与交互逻辑
; ==============================================================================
RefreshUi() {
    global BtnBrowse, BtnChinese, BtnRestore, BtnReset, EditInstallPath, g_ConfigCache, g_CurrentServer
    if (!g_CurrentServer.Has("id"))
        return

    Sec := "Server_" . g_CurrentServer["id"]
    IsPatched := (g_ConfigCache.HasOwnProp(Sec) && g_ConfigCache.%Sec%.HasOwnProp("IsPatched")) ? g_ConfigCache.%Sec%.IsPatched :
        0

    BtnChinese.Opt(IsPatched == 1 ? "+Disabled" : "-Disabled")
    BtnRestore.Opt("-Disabled")

    if (EditInstallPath.Value) {
        BtnReset.Enabled := true
        (IsPatched != 1) ? BtnChinese.Focus() : BtnRestore.Focus()
    } else {
        BtnReset.Enabled := false
        BtnScan.Focus()
    }
}

; ==============================================================================
; 安全刷新主界面
; ==============================================================================
SafeRefreshUi() {
    global g_IsDialogShowing, MainGui
    if (g_IsDialogShowing || !WinExist(MainGui))
        return
    RefreshServerComboBox()
    RefreshServerData()
}

; ==============================================================================
; 设置并规范化游戏安装目录
; ==============================================================================
SetInstallPath(NewPath, IsManualReset := 0) {
    global g_ConfigCache, g_CurrentServer, g_InstallPath, EditInstallPath, BtnChinese, BtnRestore
    Sec := "Server_" . g_CurrentServer["id"]
    NewPathNormalized := (NewPath != "") ? PathUtil.Normalize(NewPath) : ""

    if (g_InstallPath != NewPathNormalized) {
        BtnChinese.Opt("-Disabled")
        g_ConfigCache.%Sec%.IsPatched := 0
        g_ConfigCache.%Sec%.LocalPatchVersion := ""
        g_ConfigCache.%Sec%.LocalPatchBranchID := 0
    }

    g_InstallPath := NewPathNormalized
    EditInstallPath.Value := NewPathNormalized
    g_ConfigCache.%Sec%.InstallPath := NewPathNormalized
    g_ConfigCache.%Sec%.IsManualReset := IsManualReset

    SaveAllConfig()
    RefreshUi()
}

; ==============================================================================
; 切换服务器时的事件响应
; ==============================================================================
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

; ==============================================================================
; 执行一键汉化核心逻辑
; ==============================================================================
DoChinesePatch(*) {
    global g_InstallPath, g_CurrentServer, g_PatchsCacheDir, BtnChinese, g_ConfigCache

    BtnChinese.Opt("+Disabled")

    try {
        if (!g_InstallPath || !DirExist(g_InstallPath)) {
            ShowMessageDialog("请先设置 AION2 游戏的安装目录。")
            return
        }

        Branches := g_CurrentServer["patch_branches"]
        if (Branches.Length == 0) {
            ShowMessageDialog("未发现有效的汉化补丁数据。")
            return
        }

        PatchBranch := (Branches.Length == 1) ? Branches[1] : ShowMultiBranchDialog(Branches)
        if (!PatchBranch)
            return

        ActionsArray := PatchBranch["actions"]
        if (ActionsArray.Length == 0) {
            ShowMessageDialog("未发现有效的汉化补丁执行方案。")
            return
        }

        BranchId := PatchBranch["id"]

        HasAnyInstalled := false
        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            if (Act["type"] == "add" || Act["type"] == "replace") {
                if (Act["file_md5"] == "d41d8cd98f00b204e9800998ecf8427e")
                    continue
                if FileExist(PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])) {
                    HasAnyInstalled := true
                    break
                }
            }
        }
        if (HasAnyInstalled && !ShowConfirmDialog("检测到游戏目录中已存在汉化补丁文件，是否直接覆盖更新？"))
            return

        LocalCacheRootDir := PathUtil.Normalize(A_ScriptDir . "\" . g_PatchsCacheDir)
        if !DirExist(LocalCacheRootDir)
            DirCreate(LocalCacheRootDir)

        TempDownloadList := Map()
        ShowStatus("正在检查本地缓存目录中的文件 MD5...")
        AllLocalCacheValid := true

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            if (Act["type"] != "add" && Act["type"] != "replace") || (Act["file_md5"] ==
                "d41d8cd98f00b204e9800998ecf8427e")
                continue

            LocalCacheFile := GetLocalCachePath(Act["remote_filename"])
            if (!FileExist(LocalCacheFile) || Act["file_md5"] == "" || HashFileMd5(LocalCacheFile) != Act["file_md5"]) {
                AllLocalCacheValid := false
                break
            }
        }

        if (!AllLocalCacheValid)
            FindFastestDownloadNode()
        else
            ShowStatus("本地缓存全部校验通过，已跳过网络下载。")

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            if (Act["type"] != "add" && Act["type"] != "replace") || (Act["file_md5"] ==
                "d41d8cd98f00b204e9800998ecf8427e")
                continue

            RemoteFileUrl := StrReplace(Trim(Act["remote_filename"]), "\", "/")
            LocalCacheFile := GetLocalCachePath(Act["remote_filename"])
            KeyName := Act["remote_filename"]

            if (FileExist(LocalCacheFile) && Act["file_md5"] != "" && HashFileMd5(LocalCacheFile) == Act["file_md5"]) {
                TempDownloadList[KeyName] := Map("src", LocalCacheFile, "fileAction", Act)
                continue
            }

            SplitPath(LocalCacheFile, &SafeFilename)
            TmpFile := PathUtil.Normalize(A_Temp . "\" . SafeFilename . ".tmp")
            if FileExist(TmpFile)
                FileDelete(TmpFile)

            if (!DownloadSingleFileWithNode(RemoteFileUrl, TmpFile, Act)) {
                if FileExist(TmpFile)
                    FileDelete(TmpFile)
                throw Error("补丁文件 [" . RemoteFileUrl . "] 下载失败。")
            }

            if (Act["file_md5"] != "" && HashFileMd5(TmpFile) != Act["file_md5"]) {
                if FileExist(TmpFile)
                    FileDelete(TmpFile)
                throw Error("文件 [" . RemoteFileUrl . "] MD5 不匹配，补丁文件下载失败。")
            }

            if FileExist(LocalCacheFile)
                FileDelete(LocalCacheFile)
            FileMove(TmpFile, LocalCacheFile, 1)

            ShowStatus("文件 [" . RemoteFileUrl . "] 下载并校验完成。")
            TempDownloadList[KeyName] := Map("src", LocalCacheFile, "fileAction", Act)
        }

        ShowStatus("正在按规则处理游戏内部文件...")

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            FinalPath := PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])
            BackupPath := PathUtil.Normalize(A_ScriptDir . "\rawBackup\" . BranchId . "\" . Act["target_relative_path"]
            )
            SplitPath(FinalPath, , &FDir)
            SplitPath(BackupPath, , &BDir)

            if (Act["type"] == "remove") {
                if FileExist(FinalPath)
                    FileDelete(FinalPath)

            } else if (Act["type"] == "delete") {
                if FileExist(FinalPath) {
                    if (BDir != "" && !DirExist(BDir))
                        DirCreate(BDir)
                    if (!FileExist(BackupPath)) {
                        try FileCopy(FinalPath, BackupPath, 1)
                        catch
                            throw Error("备份原文件 [" . Act["target_relative_path"] . "] 失败，文件可能被占用。")
                    }
                    FileDelete(FinalPath)
                }

            } else if (Act["type"] == "add" || Act["type"] == "replace") {
                if (Act["file_md5"] == "d41d8cd98f00b204e9800998ecf8427e") {
                    if (FDir != "" && !DirExist(FDir))
                        DirCreate(FDir)

                    if (Act["type"] == "replace" && FileExist(FinalPath)) {
                        if (BDir != "" && !DirExist(BDir))
                            DirCreate(BDir)
                        if (!FileExist(BackupPath)) {
                            try FileCopy(FinalPath, BackupPath, 1)
                        }
                    }
                    WriteFileAtomic(FinalPath, "")
                    continue
                }

                KeyName := Act["remote_filename"]
                if (TempDownloadList.Has(KeyName)) {
                    if (FDir != "" && !DirExist(FDir))
                        DirCreate(FDir)

                    if (Act["type"] == "replace" && FileExist(FinalPath)) {
                        if (BDir != "" && !DirExist(BDir))
                            DirCreate(BDir)
                        if (!FileExist(BackupPath)) {
                            try FileCopy(FinalPath, BackupPath, 1)
                        }
                    }

                    try FileCopy(TempDownloadList[KeyName]["src"], FinalPath, 1)
                    catch
                        throw Error("释放补丁文件 [" . Act["target_relative_path"] . "] 失败，文件可能被占用锁死。")
                }
            }
        }

        Sec := "Server_" . g_CurrentServer["id"]
        g_ConfigCache.%Sec%.IsPatched := 1
        g_ConfigCache.%Sec%.LocalPatchVersion := PatchBranch["latest_patch_version"]
        g_ConfigCache.%Sec%.LocalPatchBranchID := BranchId
        SaveAllConfig()

        ShowMessageDialog("汉化完成，补丁文件已成功释放至游戏目录。")
    } catch Error as Err {
        ShowMessageDialog("汉化失败：`r`n" . Err.Message)
    } finally {
        RefreshUi()
    }
}

; ==============================================================================
; 撤销汉化并还原原始文件
; ==============================================================================
DoRestorePatch(*) {
    global g_InstallPath, g_CurrentServer, BtnRestore, g_ConfigCache

    try {
        if (!g_InstallPath || !DirExist(g_InstallPath))
            throw Error("请先指定 AION2 游戏的安装目录后再执行撤销操作。")

        Branches := g_CurrentServer["patch_branches"]
        if (Branches.Length == 0)
            throw Error("当前服务器未发现可用的撤销配置。")

        Sec := "Server_" . g_CurrentServer["id"]
        SavedBranchID := (g_ConfigCache.HasOwnProp(Sec) && g_ConfigCache.%Sec%.HasOwnProp("LocalPatchBranchID")) ?
            g_ConfigCache.%Sec%.LocalPatchBranchID : 0

        PatchBranch := ""
        for Branch in Branches {
            if (Branch["id"] == SavedBranchID) {
                PatchBranch := Branch
                break
            }
        }
        if (!PatchBranch && Branches.Length > 0)
            PatchBranch := Branches[1]

        ActionsArray := PatchBranch["actions"]
        if (ActionsArray.Length == 0)
            throw Error("当前补丁配置异常，缺少文件处理动作。")

        BranchId := PatchBranch["id"] ? PatchBranch["id"] : (SavedBranchID ? SavedBranchID : 1)

        HasAnyPatchFile := false
        loop ActionsArray.Length {
            if FileExist(PathUtil.Normalize(g_InstallPath . "\" . ActionsArray[A_Index]["target_relative_path"])) {
                HasAnyPatchFile := true
                break
            }
        }

        IsPatched := (g_ConfigCache.HasOwnProp(Sec) && g_ConfigCache.%Sec%.HasOwnProp("IsPatched")) ? g_ConfigCache.%Sec%.IsPatched : 0

        if (IsPatched == 0 && !HasAnyPatchFile)
            throw Error("当前游戏未应用汉化，无需执行撤销操作。")

        if (IsPatched == 1 && !HasAnyPatchFile) {
            g_ConfigCache.%Sec%.IsPatched := 0
            g_ConfigCache.%Sec%.LocalPatchVersion := ""
            g_ConfigCache.%Sec%.LocalPatchBranchID := 0
            SaveAllConfig()
            throw Error("游戏目录内未检测到汉化补丁文件。")
        }

        ShowStatus("正在还原文件并清理汉化残留...")

        loop ActionsArray.Length {
            Act := ActionsArray[A_Index]
            FinalPath := PathUtil.Normalize(g_InstallPath . "\" . Act["target_relative_path"])
            BackupPath := PathUtil.Normalize(A_ScriptDir . "\rawBackup\" . BranchId . "\" . Act["target_relative_path"]
            )
            SplitPath(FinalPath, , &FDir)

            if (Act["type"] == "add") {
                if FileExist(FinalPath) {
                    try FileDelete(FinalPath)
                    if FileExist(FinalPath)
                        throw Error("文件 [" . Act["target_relative_path"] . "] 被未知进程占用锁死，清除失败。")
                }
            } else if (Act["type"] == "replace" || Act["type"] == "delete") {
                if FileExist(BackupPath) {
                    if (FDir != "" && !DirExist(FDir))
                        DirCreate(FDir)
                    try FileCopy(BackupPath, FinalPath, 1)
                    catch
                        throw Error("还原备份文件 [" . Act["target_relative_path"] . "] 失败，可能被游戏进程占用。")
                    try FileDelete(BackupPath)
                } else if (Act["type"] == "replace" && FileExist(FinalPath)) {
                    try FileDelete(FinalPath)
                    if FileExist(FinalPath)
                        throw Error("文件 [" . Act["target_relative_path"] . "] 被未知进程占用锁死，清除失败。")
                }
            }
        }

        g_ConfigCache.%Sec%.IsPatched := 0
        g_ConfigCache.%Sec%.LocalPatchVersion := ""
        g_ConfigCache.%Sec%.LocalPatchBranchID := 0
        SaveAllConfig()

        ShowMessageDialog("撤销成功，已恢复备份文件并清除汉化补丁。")

    } catch Error as Err {
        ShowMessageDialog(Err.Message)
    } finally {
        RefreshUi()
    }
}

; ==============================================================================
; 检查客户端应用更新
; ==============================================================================
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

; ==============================================================================
; 检查云端公告更新
; ==============================================================================
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

; ==============================================================================
; 查找最快的下载镜像节点 (网络测速)
; ==============================================================================
FindFastestDownloadNode() {
    global g_CleanPreUrl, g_PatchManifestFilename, g_CleanProxyMirrors, MainStatusBar, g_BestDownloadPrefix,
        g_BestLatency

    Candidates := [
        {
            Prefix: "",
            TestUrl: g_CleanPreUrl . "/" . g_PatchManifestFilename
        }
    ]
    for Mirror in g_CleanProxyMirrors
        Candidates.Push({
            Prefix: Mirror,
            TestUrl: Mirror . "/" . g_CleanPreUrl . "/" . g_PatchManifestFilename
        })

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

    if (g_BestLatency >= 99999)
        throw Error("所有下载节点连接超时，请检查网络或开启加速器。")

    g_BestDownloadPrefix := BestNode.Prefix
    return BestNode
}

; ==============================================================================
; 获取指定 URL 链接的响应延迟 (毫秒)
; ==============================================================================
GetUrlLatency(Url, TimeoutSeconds := 2) {
    StartTime := A_TickCount
    try {
        Whr := WinHttpRequest()
        Whr.Open("HEAD", Url, true)
        Whr.SetRequestHeader("User-Agent", "Mozilla/5.0")
        Whr.Send()
        if (Whr.WaitForResponse(TimeoutSeconds)) {
            if (Whr.Status == 200 || Whr.Status == 301 || Whr.Status == 302)
                return A_TickCount - StartTime
        }
    } catch {
    }
    return 99999
}

; ==============================================================================
; 通过测速后的最佳节点单文件下载
; ==============================================================================
DownloadSingleFileWithNode(RemoteFile, DestPath, FileAction) {
    global g_CleanPreUrl, g_BestDownloadPrefix, g_BestLatency, MainStatusBar
    CleanRemotePath := LTrim(RemoteFile, "/")
    TargetUrl := (g_BestDownloadPrefix != "") ? g_BestDownloadPrefix . "/" . g_CleanPreUrl . "/" . CleanRemotePath :
        g_CleanPreUrl . "/" . CleanRemotePath
    TotalBytes := FileAction["file_size"]
    TotalSizeStr := (TotalBytes > 0) ? FormatFileSize(TotalBytes) : "未知大小"

    UpdateDownloadStatus() {
        try {
            CurrentSizeStr := FormatFileSize(FileExist(DestPath) ? FileGetSize(DestPath) : 0)
            StatusText := (TotalBytes > 0)
                ? Format("`t正在下载：{} [{} / {}] (节点: {}ms)", RemoteFile, CurrentSizeStr, TotalSizeStr, g_BestLatency)
                : Format("`t正在下载：{} [{}] (节点: {}ms)", RemoteFile, CurrentSizeStr, g_BestLatency)
            MainStatusBar.SetText(StatusText)
        }
    }

    SetTimer(UpdateDownloadStatus, 100)
    try {
        SplitPath(DestPath, , &ParentDir)
        if (ParentDir != "" && !DirExist(ParentDir))
            DirCreate(ParentDir)
        if FileExist(DestPath)
            FileDelete(DestPath)
        Download(TargetUrl, DestPath)
        SetTimer(UpdateDownloadStatus, 0)
        return (FileExist(DestPath) && FileGetSize(DestPath) > 0)
    } catch {
        SetTimer(UpdateDownloadStatus, 0)
        return false
    }
}

; ==============================================================================
; 通过代理队列 HTTP 请求获取文本内容
; ==============================================================================
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
            Whr.SetRequestHeader("User-Agent", "Mozilla/5.0")
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
; 计算文件的 MD5 哈希校验值
; ==============================================================================
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

            Loop HashLen {
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

; ==============================================================================
; 格式化文件大小字节数
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

; ==============================================================================
; 原子化写入文件
; ==============================================================================
WriteFileAtomic(FilePath, TextContent := "") {
    if IsObject(TextContent)
        TextContent := ""

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
        if FileExist(TmpFile)
            FileDelete(TmpFile)
        return false
    }
}

; ==============================================================================
; 显示状态栏提示消息并定时清除
; ==============================================================================
ShowStatus(StatusMessage) {
    global MainStatusBar
    MainStatusBar.SetText("`t" . StatusMessage)
    SetTimer(() => MainStatusBar.SetText(""), -3000)
}

; ==============================================================================
; 重置配置按钮事件
; ==============================================================================
DoResetConfig(*) {
    global g_CurrentServer
    SetInstallPath("", 1)
    ShowStatus("AION2 " . g_CurrentServer["name"] . "安装目录已重置。")
}

; ==============================================================================
; 浏览并选择安装目录按钮事件
; ==============================================================================
BrowseFolder(*) {
    global g_CurrentServer, EditInstallPath
    SelectedFolder := FileSelect("D", EditInstallPath.Value, "选择 AION2 " . g_CurrentServer["name"] . "安装目录：")
    if (SelectedFolder = "")
        return

    NormalizedSelectedFolder := PathUtil.Normalize(SelectedFolder)
    if (!FileExist(NormalizedSelectedFolder . "\Aion2\Binaries\Win64\Aion2.exe")) {
        ShowMessageDialog("所选目录中未检测主程序 Aion2.exe，请重新选择正确的安装目录。")
        return
    }
    SetInstallPath(NormalizedSelectedFolder, 0)
    ShowStatus("AION2 " . g_CurrentServer["name"] . "安装目录设置成功。")
}

; ==============================================================================
; 更新界面使用须知说明文字
; ==============================================================================
UpdateNoticeText() {
    global g_CurrentServer, TextExplain
    ServerName := g_CurrentServer["name"]
    RuleText := "1. 选择 AION2 " . ServerName . "的安装目录，" . ((g_CurrentServer["id"] = 102) ? "例如 D:\Games\AION2_TW。" :
        "例如 D:\Games\AION 2。")
    TextExplain.Value := RuleText .
        "`r`n2. 汉化完成后启动或重启 AION2，使汉化文件生效。" .
        "`r`n3. 如发生异常问题，使用“撤销汉化”功能，或在 PURPLE / Steam 修复文件；" .
        "`r`n   PURPLE : AION2 - 游戏设置 - 检查文件；" .
        "`r`n   Steam : AION2 -  属性 - 已安装的文件 - 验证游戏文件的完整性；" .
        "`r`n4. 本工具为第三方扩展，使用即代表您自愿承担所有风险。"
}

; ==============================================================================
; 显示软件更新弹窗
; ==============================================================================
ShowAppUpdateDialog(ChangelogText, DownloadUrlMain, DownloadUrlMinor, IsForceUpdate := false) {
    global MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    OldDetectState := A_DetectHiddenWindows
    UpdateGui := Gui("+Owner" . MainGui.Hwnd, "软件更新提示")
    UpdateGui.SetFont(, "Microsoft YaHei UI")

    UpdateGui.Add("Text", "x20 y20 w360", "当前软件版本过低，请下载最新版本使用。")
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

    DetectHiddenWindows false
    WinWaitClose(UpdateGui)
    DetectHiddenWindows OldDetectState

    UpdateGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
}

; ==============================================================================
; 显示云端公告弹窗
; ==============================================================================
ShowBulletinDialog(ContentText, BulletinVersion) {
    global MainGui, g_IsDialogShowing, g_LastSeenBulletinVersion
    g_IsDialogShowing := true

    OldDetectState := A_DetectHiddenWindows
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

    DetectHiddenWindows false
    WinWaitClose(BulletinGui)
    DetectHiddenWindows OldDetectState

    BulletinGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
}

; ==============================================================================
; 显示确认对话框
; ==============================================================================
ShowConfirmDialog(Text) {
    global MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    OldDetectState := A_DetectHiddenWindows
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

    DetectHiddenWindows false
    WinWaitClose(ConfirmGui)
    DetectHiddenWindows OldDetectState

    ConfirmGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
    return UserChoice
}

; ==============================================================================
; 显示普通消息提示对话框
; ==============================================================================
ShowMessageDialog(Text) {
    global MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    OldDetectState := A_DetectHiddenWindows
    ConfirmGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    ConfirmGui.SetFont(, "Microsoft YaHei UI")

    ConfirmGui.Add("Text", "x20 y20 w310 h60", Text)

    BtnConfirm := ConfirmGui.Add("Button", "x262 y102 w68 h28 Default", "确认")

    BtnConfirm.OnEvent("Click", (*) => (MainGui.Opt("-Disabled"), ConfirmGui.Hide()))
    ConfirmGui.OnEvent("Close", (*) => (MainGui.Opt("-Disabled"), ConfirmGui.Hide()))

    MainGui.Opt("+Disabled")
    ConfirmGui.Show("w350 h150")

    DetectHiddenWindows false
    WinWaitClose(ConfirmGui)
    DetectHiddenWindows OldDetectState

    ConfirmGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
}

; ==============================================================================
; 显示多补丁分支选择对话框
; ==============================================================================
ShowMultiBranchDialog(Branches) {
    global g_CurrentServer, MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    OldDetectState := A_DetectHiddenWindows
    ChoiceGui := Gui("+Owner" . MainGui.Hwnd, "提示")
    ChoiceGui.SetFont(, "Microsoft YaHei UI")

    ChoiceGui.Add("Text", "x20 y15 w410 h25", "选择 AION2 " . g_CurrentServer["name"] . " 汉化补丁来源，不同来源游戏内翻译完成度可能不同。")

    ListBoxItems := []
    for Branch in Branches {

        ret := Branch.Has("release_timestamp") ? FormatTime(DateAdd("19700101000000", Branch["release_timestamp"], "Seconds"), "yy-MM-dd HH:mm:ss") : "未知"
        Ver := Branch.Has("latest_patch_version") ? Branch["latest_patch_version"] : "1.0.0.0"
        Src := Branch.Has("source") ? Branch["source"] : "default"
        Id := Branch.Has("id") ? Branch["id"] : A_Index
        ListBoxItems.Push(Format("补丁来源 - [ {} ] -> 更新于 {}", Src, Ret))
    }

    ListControl := ChoiceGui.Add("ListBox", "x20 y45 w410 h130 r5 Choose1 +HScroll", ListBoxItems)

    BtnConfirm := ChoiceGui.Add("Button", "x262 y200 w84 h30 Default", "确认")
    BtnCancel := ChoiceGui.Add("Button", "x356 y200 w74 h30", "取消")

    SelectedBranch := ""
    BtnConfirm.OnEvent("Click", (*) => (SelectedBranch := Branches[ListControl.Value], MainGui.Opt("-Disabled"),
        ChoiceGui.Hide()))
    BtnCancel.OnEvent("Click", (*) => (SelectedBranch := "", MainGui.Opt("-Disabled"), ChoiceGui.Hide()))
    ChoiceGui.OnEvent("Close", (*) => (SelectedBranch := "", MainGui.Opt("-Disabled"), ChoiceGui.Hide()))

    MainGui.Opt("+Disabled")
    ChoiceGui.Show("w450 h250")

    DetectHiddenWindows false
    WinWaitClose(ChoiceGui)
    DetectHiddenWindows OldDetectState

    ChoiceGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
    return SelectedBranch
}

; ==============================================================================
; 显示多游戏安装路径选择对话框
; ==============================================================================
ShowMultiPathDialog(ValidGames) {
    global g_CurrentServer, MainGui, g_IsDialogShowing
    g_IsDialogShowing := true

    OldDetectState := A_DetectHiddenWindows
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

    DetectHiddenWindows false
    WinWaitClose(ChoiceGui)
    DetectHiddenWindows OldDetectState

    ChoiceGui.Destroy()
    g_IsDialogShowing := false
    RefreshUi()
    return UserChoicePath
}

; ==============================================================================
; 获取所有经过合法性校验的游戏安装路径列表
; ==============================================================================
GetValidGamePaths() {
    global g_CurrentServer

    Keywords := (Type(g_CurrentServer) == "Map" && g_CurrentServer.Has("keywords")) ? g_CurrentServer["keywords"] : [
        "AION"
    ]
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

; ==============================================================================
; 从注册表查询匹配关键字的游戏安装路径
; ==============================================================================
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

; ==============================================================================
; 点击查找按钮事件响应
; ==============================================================================
OnScanButtonClick() {
    global g_CurrentServer

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

    SetInstallPath(SelectedFolder, 0)
}

; ==============================================================================
; 静默自动检测游戏安装目录
; ==============================================================================
SilentDetectFolder() {
    global g_ConfigCache, g_CurrentServer
    SectionName := "Server_" . g_CurrentServer["id"]

    if (g_ConfigCache.%SectionName%.IsManualReset == 1)
        return

    ValidGames := GetValidGamePaths()

    if (ValidGames.Length = 1) {
        SelectedFolder := ValidGames[1].GameInstallPath
        SetInstallPath(SelectedFolder, 0)
        ShowStatus("已自动识别并设置安装目录。")
    }
}
