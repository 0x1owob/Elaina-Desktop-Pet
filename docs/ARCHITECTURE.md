# 技術結構

Elaina Desktop Pet 為單一 macOS App，使用 Swift 與 AppKit。透明 NSPanel 顯示角色，另一個小型視窗顯示短暫文字；PNG 逐幀動畫與播放設定隨 App 打包，不依賴雲端服務。

| 模組 | 用途 |
| --- | --- |
| ElainaApp.swift | 視窗、角色繪製、使用者互動與選單 |
| PetGeometry.swift | 螢幕位置、邊界與基本幾何 |
| PetBehavior.swift | 安靜陪伴、大小與全螢幕離場／返回狀態 |
| PetInteractions.swift | 抓取、搖晃、放下與生活動畫 |
| PetPresentation.swift | 雙擊短飛、像素文字量測／繪製與泡泡定位 |
| PetFullscreen.swift | 前景视窗與所在螢幕的全螢幕判斷 |
| PetNotifications.swift／ElainaNotify.swift | 選用的本機 Codex 事件接入 |
| Assets/ | 執行所需的 PNG、動畫設定、台詞與字型 |
| Tests/ | 素材、幾何、行為與文字顯示檢查 |

位置、大小與活動開關使用本機設定保存。台詞存於使用者文件資料夾，可由選單開啟編輯。

事件與動畫不建立對話佇列；全螢幕、暫停與手動隱藏優先，避免補播干擾。圖像採固定畫布及 nearest interpolation，旋轉與滑鼠命中共用座標換算。
