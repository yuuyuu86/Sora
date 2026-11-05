# Sora

現在地の天気と時刻に合わせて、Mac のデスクトップに草原の風景と天候を映し出すメニューバーアプリ。
雨や雪はウィンドウや Dock に反応し、積もった雪はカーソルで払えます。

仕様書: [docs/SPEC.md](docs/SPEC.md)

## 動作環境
- macOS 14 以降 / Swift 5.10 以降
- 天気: [Open-Meteo](https://open-meteo.com/)（APIキー不要、15分ごとに更新）

## ビルドと起動
```bash
./scripts/build-app.sh
open build/Sora.app
```
メニューバーの天気アイコンから設定します（天気の自動/手動、場所、演出の強さ、太陽・月、光の変化、音、背景）。

## 構成
| ファイル | 役割 |
|---|---|
| `SceneController` | 画面ごとに背景ウィンドウ（デスクトップレベル）とオーバーレイ（Dockより上・クリック透過）を配置し30fpsで更新 |
| `Atmosphere` | 天気の補間、時刻による光と空の色、雷 |
| `LandscapeView` | 草原（空・太陽/月・星・雲・丘・草・霧）の描画 |
| `OverlaySimulation` / `OverlayView` | 雨・雪・積雪・跳ね・カーソル反応・霧の通り道 |
| `WindowTracker` | `CGWindowListCopyWindowInfo` でウィンドウ位置を取得（画面収録権限不要） |
| `WeatherService` | 位置情報・Open-Meteo・都市検索 |
| `SoundEngine` | 雨・風・雷の音をノイズから合成 |

## 暫定仕様
- 位置情報を許可しない場合は東京（手動で都市を検索可能）
- 複数ディスプレイでは全画面に同じ風景
- Dock は画面下に表示されている場合のみ雪が積もる
