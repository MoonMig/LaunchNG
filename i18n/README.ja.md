# LaunchNG

**言語**: [English](../README.md) | [简体中文](README.zh.md) | [繁體中文](README.zh-TW.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

macOS Tahoe（26）は Launchpad を完全に廃止しました。LaunchNG はそれをネイティブアプリとして復活させます。初回起動時に macOS 自身のデータベースから既存の Launchpad レイアウトをそのまま読み込み、Core Animation で描画するグリッドの上にページ送り・フォルダ・検索・ドラッグ＆ドロップによる並べ替えを独自に実装。Dock との連携、CLI/TUI の同梱、署名済みのアプリ内自動アップデートまで備えています。

## ダウンロード

**[最新リリースを取得](https://github.com/moonmig/LaunchNG/releases/latest)**

便利だと感じたら、リポジトリへの star をいただけると励みになります。LaunchNG はもともと RoversX 氏の [LaunchNext](https://github.com/RoversX/LaunchNext) からフォークしたプロジェクトです——オリジナルへの star もぜひ。

<!-- スクリーンショットはここに入ります。最新のものを提供いただける場合は「貢献」セクションをご覧ください。 -->

### macOS がアプリの起動をブロックする場合

このフォークのリリースは未署名／ad-hoc ビルドです（有料の Apple Developer アカウントを使用していません）。そのため Gatekeeper は、一度検疫フラグを解除するまでアプリの起動を拒否します：

```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNG.app
```

このコマンドは、信頼できるアプリに対してのみ実行してください。macOS のダウンロード検疫チェックをそのアプリに限って無効化します。

ソースからビルドする場合は、このコマンドは不要です。下記の[ローカル署名の設定](#configure-local-code-signing)を参照してください。

## LaunchNG でできること

- **既存の Launchpad データベースからワンクリックで移行** —— `/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db` を直接読み込み、既存のフォルダ、位置、ページ構成を正確に復元
- **クラシックなページ送りグリッド体験** —— 検索、キーボード操作、ドラッグ＆ドロップでの並べ替え、あるアイコンを別のアイコンにドラッグすることでフォルダを作成
- **全面的に Core Animation で描画**、Dock への直接ドラッグ、macOS 26 のネイティブ Liquid Glass フォルダアイコンにも対応
- **フォルダのレイアウト**：オリジナルと同じページ送り、または垂直スクロールから選択可能
- **あいまい検索**、CJK（ピンインなど）の変換にも対応しており、入力が不完全・不正確でも目的のアプリを見つけられる
- **ホットコーナーとトラックパッドジェスチャーによる起動**、実験的な 4本／5本指ピンチ・タップにも対応
- **CLI と TUI** でターミナルからレイアウトを確認・操作可能
- **[Sparkle](https://sparkle-project.org) による署名済み自動アップデート**、アプリ内の通常の「アップデートを確認」ボタンから利用可能
- **選んだフォルダへのローカルバックアップ**、復元可能な履歴も管理
- **アイコンラベルの非表示、アイコンサイズと間隔の調整** —— メイングリッドとフォルダ内でそれぞれ個別に設定可能
- **13 言語**の完全な UI 翻訳（上記の言語一覧を参照）
- **強化されたコンテキストメニュー** —— Finder で表示、アプリのパスをコピー、フォルダ名の変更、そして（オプションで）信頼できる他のアプリの Gatekeeper 検疫を解除するショートカット
- **コントローラーと音声フィードバックのサポート**、アクセシビリティに配慮

## macOS Tahoe が奪ったもの

- ユーザーによるフォルダ作成や自由な整理ができない
- ドラッグ＆ドロップでの並べ替えができない
- 視覚的なアプリ管理が一切ない——自動生成されアルファベット順に並んだ、触れないグリッドのみ

LaunchNG が存在するのは、これが妥当なデフォルト仕様ではなく、明らかな機能低下だからです。

## データの保存場所

LaunchNG 自身のレイアウト、環境設定、キャッシュは以下に保存されます：

```
~/Library/Application Support/LaunchNG/Data.store
```

データはどこにも送信されません。唯一のネットワーク通信はアップデートフィードの確認と、あなたが実行を選んだ場合のみ発生する Apple 自身の Launchpad データベースの読み込みです：

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## インストール

### 動作環境

- macOS 26（Tahoe）以降
- Apple Silicon または Intel
- ソースからビルドする場合は Xcode 26

### ソースからビルド

```bash
git clone https://github.com/moonmig/LaunchNG.git
cd LaunchNG
open LaunchNG.xcodeproj
```

<a name="configure-local-code-signing"></a>**ローカル署名の設定**（有料の Apple Developer アカウントは不要）：

- **LaunchNG** ターゲットを選択 → **Signing & Capabilities** → **Team** を `None` に、証明書を `Sign to Run Locally` に設定。Hardened Runtime は有効のままにしてください。
- この変更後、Xcode はプロジェクトファイルを変更済みとしてマークします——署名関連のみの変更は pull request に含めないでください。

`⌘R` で実行するには、実行先を **My Mac** にする必要があります——ユニバーサル／「Any Mac」ではビルド・アーカイブはできてもデバッグ実行はできません。ビルドのみなら `⌘B`。

### コマンドラインでのビルド

```bash
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release

# ユニバーサルバイナリ（Apple Silicon + Intel）：
xcodebuild -project LaunchNG.xcodeproj -scheme LaunchNG -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 使い方

1. **初回起動時**にインストール済みアプリを自動的にスキャンします。
2. **設定 → General → Import System Launchpad** で、既存のレイアウト・フォルダ・配置をワンクリックで取り込みます。
3. クリックで選択、ダブルクリック（または Return）で起動。どこでも入力すれば検索開始。
4. あるアプリを別のアプリにドラッグしてフォルダを作成。アプリをドラッグして並べ替え。
5. ターミナルからレイアウトを操作したい場合は、設定で CLI を有効にできます。

### フルスクリーンとコンパクト

- **フルスクリーン**は画面全体を覆い、オリジナルの Launchpad に最も近い見た目です。
- **コンパクト**は角丸の浮動ウィンドウで、サイズ変更が可能です。
- 外観設定（アイコンの拡大率、間隔、ページインジケーターの位置など）はモードごとに個別に保存されます。
- フルスクリーンではメニューバーを非表示にでき、その場合 Dock も macOS が自動的に隠します。

## 主な設定項目

- **外観**：アイコンの拡大率、ラベルのサイズと表示／非表示、グリッド間隔——フォルダ内容は個別の値を設定可能——および背景スタイル（ぼかし、ネイティブ Liquid Glass、またはライブ壁紙ベースの背景）
- **検索**：あいまい検索の切り替えと検索のデバウンス時間
- **非表示アプリ**：アンインストールせずに特定のアプリをグリッドから除外
- **バックアップ**：フォルダを選択し、タイムスタンプ付きバックアップを作成、一覧から復元・削除
- **ショートカットとジェスチャー**：グローバルホットキー、ホットコーナー、（実験的な）トラックパッドジェスチャーの割り当て
- **アップデート**：自動確認の切り替えと手動の「アップデートを確認」ボタン、いずれも Sparkle 対応

## トラブルシューティング

**アプリが起動しない。** macOS 26.0 以降であることと、検疫フラグが解除済みであることを確認してください（上記参照）。

**「アップデートを確認」でエラーが出る。** LaunchNG は署名済みアップデートフィードを持つ Sparkle を使用しています。手動チェックは、数分以内に最新リリースを正しく反映するはずです。

**ターミナルに `launchng` コマンドがない。** これはオプション機能です——まず設定でコマンドラインインターフェースを有効にしてください。LaunchNG が管理されたコマンドを自動的にインストール（後で削除も可能）します。

## コントリビューション

1. リポジトリを fork
2. 機能用のブランチを作成（`git checkout -b feature/your-feature`）
3. わかりやすいメッセージでコミット
4. ブランチを push して pull request を作成

レビューがスムーズに進むためのポイント：
- 署名関連のみの Xcode プロジェクト変更を diff に含めない（上記のローカル署名の設定を参照）
- Core Animation グリッドを変更する場合は、まず `GridReorderPlan.swift` を確認してください——並べ替え／ページングのロジックはここに集約すべきで、各ビューに重複実装しないこと
- PR を開く前にテストスイートを実行：
  ```bash
  xcodebuild test -scheme LaunchNG -destination 'platform=macOS'
  ```

最新の正確なスクリーンショット（メイングリッド、設定タブいくつか）の提供も、非常に価値のある貢献です——このファイル冒頭のプレースホルダーを参照してください。

### 関連ドキュメント

- [Folder Liquid Glass](../Documentation/FolderLiquidGlass.md) —— フォルダのガラス風アイコンの設計上の制約、検証済みの内容、そして受け入れテストがまだ必要な部分
- [Grid diagnostics](../scripts/diagnostics/README.md) —— グリッドとガラスオーバーレイの手動検証ツールと、その正確なカバレッジと制限

## ライセンスと謝辞

LaunchNG は RoversX 氏の [LaunchNext](https://github.com/RoversX/LaunchNext) のフォークであり、それ自体もさらに広範な Launchpad 代替プロジェクトのコミュニティにルーツを持ちます。両プロジェクトとも GPL-3.0 でライセンスされており、LaunchNG も同じ条件に従います——詳細は [LICENSE](../LICENSE) を参照してください。

実験的なトラックパッドジェスチャー機能は [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) および [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) 氏によるフォークをベースにしています。

---

![GitHub downloads](https://img.shields.io/github/downloads/moonmig/LaunchNG/total)
