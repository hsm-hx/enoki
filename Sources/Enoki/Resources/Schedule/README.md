# イベント日程の置き場（データは同梱していません）

見た目プロファイルの「イベント日」判定（`DayProfileResolver` / `MatchPhase`）が読む
日程データ `renofa-schedule.json` の置き場所です。

**このリポジトリには日程データを含めていません。** 中身は開発者個人の環境に依存し、
第三者のサイトから写した日付・対戦相手などを含むためです。
**個人データとして各自のマシンに置いてください。**

## 置き場所（先に見つかったほうを使います）

| 場所 | 用途 |
|---|---|
| `~/Library/Application Support/Enoki/renofa-schedule.json` | **推奨。** アプリを作り直さずに差し替えられます |
| このフォルダ（`Sources/Enoki/Resources/Schedule/renofa-schedule.json`） | 自分のビルドに同梱したい場合。`.gitignore` 済みなのでコミットされません |

どちらにも無ければ、イベント日の判定は行われません（曜日と祝日だけで見た目が決まります）。
アプリは**ネットワークに一切アクセスしません**。日程はローカルの JSON だけが情報源です。

## 形式

```json
{
  "schema_version": 1,
  "team": "my-team",
  "season": "2026",
  "source": "manual",
  "updated_at": "2026-01-01",
  "matches": [
    {"date": "2026-03-01", "kickoff": "14:00", "opponent": "対戦相手A", "home": true,
     "competition": "リーグ戦", "venue": "ホームスタジアム"},
    {"date": "2026-03-08", "opponent": "対戦相手B", "home": false}
  ]
}
```

| キー | 必須 | 意味 |
|---|---|---|
| `date` | **必須** | `yyyy-MM-dd`。この書式でないとその 1 件だけ捨てられます |
| `opponent` | **必須** | 相手の名前（メニューの「今日:」表示に出ます） |
| `home` | 任意 | ホームなら `true`（既定 `false`）。表示の `(H)` / `(A)` に使います |
| `kickoff` | 任意 | `HH:mm`。**これがある日だけ**「開始前 → 進行中 → 終了後」の局面が切り替わります。無ければ終日「イベント日」扱い |
| `competition` / `venue` / `note` | 任意 | 表示・メモ用 |
| `team` / `season` / `source` / `updated_at` | 任意 | ファイル自身のメモ。`source` には取得元 URL か `"manual"` を書いておくと後で困りません |

壊れた項目はその 1 件だけが読み飛ばされ、残りは読み込まれます（理由は `os.Logger` の
category `appearance` に出ます）。

仕組みの詳細は [docs/architecture.md](../../../../docs/architecture.md) の §12.9、
自分のイベント差分の作り方は [docs/customization.md](../../../../docs/customization.md) の 6 章を参照してください。

> このファイルは、SwiftPM が空フォルダを扱えないためのプレースホルダも兼ねています。削除しないでください。
