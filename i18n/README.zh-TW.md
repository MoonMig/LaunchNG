# LaunchNG

**語言**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe（26）徹底移除了 Launchpad。LaunchNG 把它以原生應用的形式帶了回來：首次執行時直接從 macOS 自身的資料庫讀取你原本的 Launchpad 版面配置，接著在以 Core Animation 繪製的網格之上，自行實作分頁、資料夾、搜尋與拖曳排序，並整合 Dock、內建 CLI/TUI，以及應用內的簽章自動更新。

## 下載

**[取得最新版本](https://github.com/moonmig/LaunchNG/releases/latest)**

如果這個應用對你有幫助，歡迎給個 star。LaunchNG 最初是 RoversX 的 [LaunchNext](https://github.com/RoversX/LaunchNext) 的分支——原專案也值得一個 star。

<!-- 螢幕截圖將放在這裡——如果你願意提供最新截圖，請見「貢獻」章節。 -->

### 如果 macOS 阻擋應用啟動

本專案發布的是未簽章／ad-hoc 建置（這個分支沒有使用付費的 Apple 開發者帳號），因此 Gatekeeper 會拒絕開啟應用，直到你手動清除一次隔離標記：

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

請只對你信任的應用執行這個指令——它會關閉 macOS 對該應用的下載隔離檢查。

從原始碼建置？請見下方的[設定本機程式碼簽章](#configure-local-code-signing)，你不需要這個指令。

## LaunchNG 能做什麼

- **一鍵從真實 Launchpad 資料庫匯入** —— 直接讀取 `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db`，精確還原你現有的資料夾、位置與分頁
- **經典的分頁網格體驗** —— 搜尋、鍵盤導覽、拖曳排序，把一個圖示拖到另一個上即可建立資料夾
- **全程以 Core Animation 繪製**，包括直接拖曳到 Dock，以及 macOS 26 上原生的 Liquid Glass 資料夾圖示
- **資料夾版面**：分頁（如原版）或垂直捲動，任你選擇
- **模糊搜尋**，支援 CJK（拼音等）轉寫比對，即使輸入不完整或不準確也能找到應用
- **熱角與觸控板手勢啟動**，包括實驗性的四指／五指捏合與點按支援
- **CLI 與 TUI**，可在終端機中檢視或操作你的版面配置
- **透過 [Sparkle](https://sparkle-project.org) 實現的簽章自動更新**，應用內提供一般的「檢查更新」按鈕
- **本機備份**到你指定的資料夾，並保留可供還原的歷史紀錄
- **隱藏圖示標籤、調整圖示大小與間距** —— 主網格與資料夾內容可分別設定
- **13 種語言**的完整介面翻譯（見上方語言清單）
- **更完善的右鍵選單** —— 在 Finder 中顯示、複製應用路徑、重新命名資料夾，以及（可選）為其他受信任應用解除 Gatekeeper 隔離的捷徑
- **搖桿與語音回饋支援**，照顧無障礙使用情境

## macOS Tahoe 拿走了什麼

- 沒有使用者自建資料夾，也無法自由組織
- 無法拖曳調整順序
- 完全沒有視覺化的應用管理——只有一個自動產生、依字母排序、你動不了的網格

LaunchNG 之所以存在，是因為這確實是一種退步，而不是合理的預設設計。

## 資料存放在哪裡

LaunchNG 自身的版面配置、偏好設定與快取儲存在：

```
~/Library/Application Support/LaunchNG/Data.store
```

不會把任何資料傳送到任何地方。唯一的網路活動是檢查更新來源，以及——當你主動觸發時——讀取 Apple 自己的 Launchpad 資料庫：

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## 安裝

### 系統需求

- macOS 26（Tahoe）或更新版本
- Apple Silicon 或 Intel 處理器
- 如需從原始碼建置，需要 Xcode 26

### 從原始碼建置

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**設定本機程式碼簽章**（不需要付費的 Apple 開發者帳號）：

- 選擇 **LaunchNG** target → **Signing & Capabilities** → 將 **Team** 設為 `None`，簽章憑證選 `Sign to Run Locally`。Hardened Runtime 保持開啟。
- 修改後 Xcode 會把專案檔標記為已修改——請不要把僅與簽章相關的變更放進 pull request。

要用 `⌘R` 執行，目標裝置必須是 **My Mac**——通用／「Any Mac」目標可以建置與封存，但無法用於偵錯執行。只需要建置時按 `⌘B`。

### 命令列建置

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# 通用二進位檔（Apple Silicon + Intel）：
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 使用方式

1. **首次啟動**時會自動掃描已安裝的應用。
2. **設定 → General → Import System Launchpad**，一鍵匯入你現有的版面配置、資料夾與位置。
3. 單擊選取，雙擊（或按 Return）啟動；隨時輸入即可搜尋。
4. 把一個應用拖到另一個上建立資料夾；拖曳應用可調整順序。
5. 如果想在終端機中腳本化操作版面配置，可在設定中啟用 CLI。

### 全螢幕與精簡模式

- **全螢幕**模式佔滿整個螢幕，最接近原版 Launchpad。
- **精簡**模式是一個可調整大小、帶圓角的浮動視窗。
- 外觀設定（圖示縮放、間距、分頁指示器位置等）在兩種模式下分別記錄。
- 全螢幕模式下可選擇隱藏選單列；開啟後 macOS 會自動隱藏 Dock。

## 值得留意的設定

- **外觀**：圖示縮放、標籤大小與顯示與否、網格間距——資料夾內容可單獨設定——以及背景樣式（模糊、原生 Liquid Glass，或以動態桌布為基礎的背景）
- **搜尋**：模糊比對開關與搜尋防彈跳延遲
- **隱藏應用**：不需解除安裝即可把特定應用從網格中隱藏
- **備份**：選擇資料夾、建立含時間戳記的備份，並可從清單中還原或刪除舊備份
- **快速鍵與手勢**：全域快速鍵、熱角，以及（實驗性的）觸控板手勢綁定
- **更新**：自動檢查開關與手動「檢查更新」按鈕，皆以 Sparkle 為基礎

## 疑難排解

**應用無法啟動。** 請確認系統為 macOS 26.0 或更新版本，且已清除隔離標記（見上文）。

**「檢查更新」顯示錯誤。** LaunchNG 使用帶簽章更新來源的 Sparkle；手動檢查應該總能在幾分鐘內反映最新發布的版本。

**終端機裡沒有 `launchng` 指令。** 這是可選功能——請先在設定中啟用命令列介面，LaunchNG 會自動安裝（之後也能自行移除）受管理的指令。

## 參與貢獻

1. Fork 本儲存庫
2. 建立功能分支（`git checkout -b feature/your-feature`）
3. 提交清楚的變更說明
4. 推送分支並開啟 pull request

有助於審查順利進行的幾點建議：
- 不要把僅與簽章相關的 Xcode 專案變更帶入 diff（見上方本機程式碼簽章章節）
- 如果變更 Core Animation 網格，先看看 `GridReorderPlan.swift`——排序／分頁邏輯應該集中在那裡，而不是在各個 view 裡重複實作
- 送出 PR 前先跑一遍測試：
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

提供新鮮、準確的螢幕截圖（主網格、幾個設定頁面）同樣是很有價值的貢獻——見本文件開頭的預留說明。

### 更多文件

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) —— 資料夾玻璃圖示背後的設計限制、已驗證的內容，以及仍待驗收的部分
- [Grid diagnostics](../scripts/diagnostics/README.md) —— 網格與玻璃疊層的手動探測工具，及其確切涵蓋範圍與限制

## 授權與致謝

LaunchNG 是 RoversX 的 [LaunchNext](https://github.com/RoversX/LaunchNext) 的分支，而後者又源自更廣泛的 Launchpad 替代方案社群專案。兩者皆採用 GPL-3.0 授權，LaunchNG 遵循相同條款——詳見 [LICENSE](../LICENSE)。

實驗性觸控板手勢支援基於 [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) 及 [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) 的分支建置。

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
