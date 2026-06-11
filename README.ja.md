# LabCapture

[English](README.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md) | **日本語** | [Español](README.es.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift) ![License: MIT](https://img.shields.io/badge/License-MIT-green) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

**公開でビルドする。ワークフローを邪魔しない。**

LabCaptureはmacOSのメニューバーアプリです。仕事をしながら、画面とウェブカメラを約3秒ごとに自動的に記録し、その映像をすぐに共有できるコンテンツに変換します。GIF、円形のカメラオーバーレイ付きの高品質な日単位のタイムラプス、そしてAI生成のビルドジャーナルです。

ビルドしている間、このアプリがキャプチャします。1日の終わりには、1080pのタイムラプス、シェア可能なGIF、そしてあなたが何をしたかを示すMarkdownジャーナルが手に入ります。すべてあなたのマシン上で生成されます。

## 何が得られるか

キャプチャするたびに（デフォルト：20分ごと、加えて`git push`のたびに）、`YYYY-MM-DD_HHmmss_*`という名前のファイルが生成されます。

- `*_screen.gif` — スクリーン（幅960px、タイムスタンプ付き）
- `*_face.gif` — ウェブカメラ
- `*_combo.gif` — スクリーンに**円形のカメラ**オーバーレイが付いたもの（ライムグリーンのリング、ピクチャインピクチャ）
- `*_screen.mp4` / `*_face.mp4` — 高品質オリジナル（CRF 18、30 fps）

そして1日1回（1クリックまたはAPIコール1回）：

- **タイムラプス** — 本日のすべてのキャプチャを1つの1080p/30fps MP4に合成：バックグラウンドとしてあなたのスクリーン、中央に円形のあなたの顔、セグメント単位のタイムスタンプ
- **ビルドジャーナル** — Claudeがキャプチャマニフェストとキーフレームを読み込んで`summary.md`を生成：1行の概要、実装内容のタイムライン、X/Twitterへの提案投稿1～2個
- **クリップボードヘルパー** — 最後のキャプチャをコピーして⌘Vで投稿に直接貼り付け

## プライバシーと安全を最優先

このツールはスクリーンを記録するため、パラノイアレベルで設計されています。

- **100%ローカル。** アカウントなし、テレメトリなし、アップロードなし。ファイルは`~/LabCapture`にのみ存在します。唯一のオプショナルなネットワーク呼び出しはビルドジャーナルで、これはあなたがトリガーしたときだけClaudeのAPI経由でデータを送信します。
- **シークレットガード（OCR）。** 各記録直後、Apple VisionのOCRがフレームをスキャンします。APIキー、トークン、パスワード、またはDB接続文字列が画面に見える場合、**キャプチャ全体が破棄**され、再試行されます。連続して3回破棄されると、キャプチャが数時間一時停止します（設定可能）。対応パターン：`sk-...`キー、GitHub PAT、AWSキー、Slack/Notionトークン、JWT、PRIVATEキーブロック、Bearerトークン、`API_KEY=`環境変数割り当てなど——意図的に幅広いマッチングを使用しています。過度な検出が安全な方向だからです。
- **キャプチャ前の警告。** オプションの通知がキャプチャの数秒前に発火するため、意図せずに記録されることはありません。
- **いたるところにキルスイッチ。** メニューバー（またはAPI）からスクリーン/フェースソースを独立してトグル、1時間一時停止、本日中一時停止、夜間スケジュール設定。スクリーンがロック中またはスリープ中はキャプチャが自動スキップされます。
- **何もコミットされない。** リポジトリの`.gitignore`がすべてのメディアファイルをブロックしており、出力フォルダはリポジトリの外にあります。

## 必要要件

- macOS 14以上（Apple Silicon）
- ffmpeg：`brew install ffmpeg`
- Xcode Command Line Tools（ビルド用）：`xcode-select --install`

## インストール

```bash
git clone https://github.com/Joonsense/labcapture.git
cd labcapture
./build.sh
open dist/LabCapture.app
```

初回起動時、オンボーディングウィンドウが必要な2つの権限を案内します。

| 権限 | 場所 | 用途 |
|---|---|---|
| Screen Recording | System Settings → Privacy & Security | スクリーンキャプチャ（ffmpegの子プロセス） |
| Camera | System Settings → Privacy & Security | ウェブカメラキャプチャ |

ヒント：

- ビルト済みの`dist/LabCapture.app`の実行中に権限を付与します（ターミナルビルドではなく）——TCCは権限を個別に追跡します。
- キャプチャが失敗しており、トグルが有効に見える場合、権限レコードが古い可能性があります：`tccutil reset ScreenCapture com.deblockx.labcapture`を実行してから再度権限を付与します。ローカル署名証明書の作成方法については[docs/SIGNING.md](docs/SIGNING.md)を参照してください。これにより権限が**リビルド時も保持**されます（ソースをいじる場合は推奨）。
- 権限がない場合、キャプチャは通知とともに安全にスキップされます——クラッシュはありません。

## 使用方法

- **自動** — デフォルトで20分ごとにキャプチャ（5～120分で設定可能）
- **メニューバー** — 今すぐキャプチャ / 一時停止（1時間、本日） / 最後のキャプチャを表示 / 本日のフォルダを開く / 設定
- **グローバルホットキー** — デフォルトで`⌃⌥⌘C`（再バインド可能）
- **静寂時間** — 例：21:00～09:00のタイマーキャプチャを一時停止（手動キャプチャは機能）
- ロック中/スリープ中は自動スキップ、および空きディスク容量が500MBを下回った場合も自動スキップ

### メニューバーアイコン

2つの形：**矩形=スクリーンソース、円=フェースソース**。塗りつぶし=オン、枠線+スラッシュ=オフ。色は全体の状態を示します：🟢ライムアクティブ·⚪グレー一時停止·🔴赤キャプチャ中·🟠オレンジ最後のキャプチャ失敗。

## 出力レイアウト

```
~/LabCapture/
  2026-06-12/
    2026-06-12_143012_screen.gif
    2026-06-12_143012_face.gif
    2026-06-12_143012_combo.gif
    2026-06-12_143012_screen.mp4     ← "オリジナルを保持"がオン（デフォルト）
    2026-06-12_143012_face.mp4
    timelapse_2026-06-12_213000.mp4  ← 日単位のタイムラプス
    summary.md                       ← AIビルドジャーナル
    manifest.jsonl                   ← キャプチャ1行ごとのJSON
  labcapture.log
```

## HTTP API――人間*および*AIエージェント用に構築

アプリは`http://127.0.0.1:48620`でリッスンします（ループバックのみ、決して公開されません）。**LLMエージェントは`GET /capabilities`への単一呼び出しから完全なAPIを検出できます**――機械可読仕様を返します。

| メソッド | パス | アクション |
|---|---|---|
| GET | `/capabilities` | 機械可読API仕様 |
| GET | `/status` | 状態（`active/paused/capturing/warning`）、ソース、次のキャプチャ時刻、最後のエラー/ファイル |
| POST | `/capture` | 今すぐキャプチャ（202；ビジー中は409）。`GET/POST /trigger`はgitフック用のエイリアス |
| POST | `/source/screen/on` · `/off` | スクリーンソースをトグル |
| POST | `/source/face/on` · `/off` | フェース（ウェブカメラ）をトグル |
| POST | `/pause` · `/pause/today` · `/resume` | 1時間一時停止 / 真夜中まで / 再開 |
| POST | `/last/copy` | 最後のcombo.gifをクリップボードにコピー（Xに⌘V） |
| POST | `/timelapse` | 本日のオリジナルを1080pタイムラプスにコンパイル（202） |
| POST | `/summary` | 本日のAIビルドジャーナルを生成（202；APIキーなしは400） |

```bash
curl -s http://127.0.0.1:48620/status | jq .sources
curl -s -X POST http://127.0.0.1:48620/source/face/off   # スクリーンのみのキャプチャ
curl -s -X POST http://127.0.0.1:48620/capture
```

### git pushのたびにキャプチャ

```bash
# <your-repo>/.git/hooks/pre-push  (chmod +x)
#!/bin/sh
curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null 2>&1 || true
exit 0
```

または成功したpush直後に発火するグローバルエイリアスとして：

```bash
git config --global alias.pushc '!git push "$@" && curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null; true'
```

## AIビルドジャーナル（オプション）

Claudeの APIキーを設定します（ハードコーディング不可——ファイルまたは環境変数）：

```bash
mkdir -p ~/.config/labcapture && printf '%s' 'sk-ant-...' > ~/.config/labcapture/anthropic_api_key && chmod 600 ~/.config/labcapture/anthropic_api_key
```

その後、メニューで「Daily wrap-up」をクリック（または`POST /summary`）して、`manifest.jsonl`と最大6つの代表的なフレームをClaudeに送信し、`summary.md`を生成します：1行の概要、作業タイムライン、およびあなたのキャプチャに実際に映っているものに基づいたX投稿の提案。

## 設定

| 設定 | デフォルト | 範囲 |
|---|---|---|
| キャプチャ間隔 | 20分 | 5～120 |
| キャプチャ長 | 3秒 | 1～5 |
| キャプチャ前の通知 / リードタイム | オン / 3秒 | 0～10秒 |
| ウェブカメラキャプチャ | オン | オフ→スクリーンのみ |
| PiP位置（combo GIF） | 右下 | tl / tr / bl / br |
| GIF fps | 15 | 8～15 |
| スクリーンGIF幅 | 960px | 480～1080 |
| 出力フォルダ | `~/LabCapture` | 任意 |
| オリジナルmp4を保持 | オン | オフ→タイムラプスはGIF にフォールバック（低品質） |
| 静寂時間 | オフ | 開始/終了時刻 |
| グローバルホットキー | ⌃⌥⌘C | 再バインド可能 |
| シークレットガード（OCR） | オン | 3回の破棄後1～12時間一時停止 |

すべての設定は`UserDefaults`を介して永続化されます。

## manifest.jsonlスキーマ（LLMパイプライン入力）

1キャプチャごとにJSONライン1行、`schema: 1`：

```json
{"schema":1,"ts":"2026-06-12T18:25:23+09:00","trigger":"push","duration":3,
 "sources":["screen","face"],
 "files":["2026-06-12_182523_screen.gif","2026-06-12_182523_face.gif","2026-06-12_182523_combo.gif"],
 "kinds":{"2026-06-12_182523_screen.gif":"screen","2026-06-12_182523_face.gif":"face","2026-06-12_182523_combo.gif":"combo"}}
```

`trigger`：`timer` / `manual` / `hotkey` / `push`（git統合）

## アーキテクチャ

Swift/SwiftUIメニューバーアプリが調整します。記録/エンコーディングはffmpegのサブプロセスに委譲されます。

```
Sources/LabCapture/
  LabCaptureApp.swift    エントリー（MenuBarExtra + Settings scene）
  AppModel.swift         中央状態：タイマー/一時停止/ロック検出/エラーログ/オンボーディング
  CaptureEngine.swift    記録→3つのGIF→マニフェスト（コアパイプライン）
  DailyPipeline.swift    タイムラプス + Claudeジャーナル + クリップボードヘルパー
  FFmpeg.swift           ffmpegプロセスランナー + avfoundationデバイス検出
  OCRGuard.swift         Vision OCRシークレット検出
  TriggerServer.swift    127.0.0.1:48620 HTTPサーバー
  HotkeyManager.swift    Carbon グローバルホットキー
  Permissions.swift      TCC確認 / 設定ディープリンク
  Views/                 メニュー / 設定 / オンボーディングUI
```

エンコーディング詳細：2パスGIFパレット（`palettegen stats_mode=diff` → `paletteuse` sierra2_4a ディザリング）；`geq`アルファによるフェザーエッジ付きの円形フェースマスク；タイムラプセグメントは1080p/30fpsに正規化してからロスレス連結；タイムスタンプは`drawtext` + `textfile=`経由（filtergrraphコロンエスケープを回避）。

## トラブルシューティング

- **「ビデオデバイスの構成に失敗しました」** （Screen Recordingトグルがオンに見える）→ 古いTCCレコード（アプリが再署名された）。修正：`tccutil reset ScreenCapture com.deblockx.labcapture`を実行して再起動し、再度権限を付与します。[ローカル署名証明書](docs/SIGNING.md)を使用して永続的に防止します。
- **ffmpegが見つかりません** → `brew install ffmpeg`（`/opt/homebrew/bin/ffmpeg`に置かれることが期待されます）。
- エラーは`~/LabCapture/labcapture.log`にログされます（メニューからも表示可能）。

## ロードマップ

- ffmpegバンドリング（ゼロ依存関係インストール）
- 公証済みリリース
- マルチモニター選択（現在はメインディスプレイ）
- Intel mac対応

PRを歓迎します。

## ライセンス

[MIT](LICENSE) © DeblockX Labs
