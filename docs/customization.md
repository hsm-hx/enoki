# 自分のキャラクターで Enoki を使う

Enoki は **台詞（`dialogue.json`）** と **スプライトシート（画像）** を差し替えれば、
同梱のデモキャラクター以外でも動かせます。このドキュメントは、その手順と仕様をまとめたものです。

同梱しているのは **デモ用キャラクター「栞」1 体**（`Sources/Enoki/Resources/DefaultSkin/`）だけです。
開発者が普段使っている御影朔・御影栞のアセットはこのリポジトリに含めていません。

> 同梱のデモアセット（栞のイラスト・スプライト）と `dialogue.json` の台詞は MIT License の対象外です。
> 自分のキャラクターに差し替えて使う場合の条件は [ASSETS_LICENSE.md](../ASSETS_LICENSE.md) を読んでください。

差し替えには 2 つの道があります。

| 方法 | 何をするか | 向いている場面 |
|---|---|---|
| **A. 外から差し替える**（推奨） | `~/.codex/pets/<名前>/` などに自分のスプライトセットと `dialogue.json` を置く | ビルドし直さずに試したい。フォークを汚したくない |
| **B. 同梱素材を置き換える** | `Sources/Enoki/Resources/` のファイルを直接差し替えて `make app` | 自分のキャラクター版を配布用にビルドしたい |

A なら Swift のコードにも同梱ファイルにも触りません。まずは A で試すのがおすすめです。

---

## 1. ファイルの探索順（どこに置けば読まれるか）

### ベーススキン（標準の見た目）

`SkinLoader.resolve` が上から順に探し、**最初に読めたもの**を使います
（`Sources/EnokiCore/Skin/SkinLoader.swift`）。

1. 環境変数 `ENOKI_SKIN_DIR` のフォルダ（開発用）
2. メニュー「スキン > フォルダを選択…」で選んだフォルダ（`UserDefaults`）
3. `~/.codex/pets/sakushio_pet/`
4. アプリ内蔵の `DefaultSkin`（リポジトリでは `Sources/Enoki/Resources/DefaultSkin/`）

### 台詞（`dialogue.json`）

`ConversationCoordinator.loadDialogue` が上から順に探します。

1. **使用中のスキンフォルダ内の `dialogue.json`**（例: `~/.codex/pets/my_pet/dialogue.json`）
2. アプリ内蔵の `DialogueText/dialogue.json`（リポジトリでは `Sources/Enoki/Resources/DialogueText/dialogue.json`）

つまり、自分のスキンフォルダに `dialogue.json` を一緒に置けば、内蔵の台詞を上書きできます。
編集したらメニューの「スキン > 再読み込み」で読み直します（ファイル監視はありません）。

### 見た目プロファイル用のスプライトセット

`profiles.json` の `spriteSet`（= フォルダ名）を、上から順に探します。

1. `~/.codex/pets/<spriteSet>/`
2. `~/Library/Application Support/Enoki/Characters/<spriteSet>/`
3. アプリ内蔵の `Characters/<spriteSet>/`（リポジトリでは `Sources/Enoki/Resources/Characters/<spriteSet>/`）

どこにも無ければ**ベーススキンにフォールバック**します（アプリは止まりません。
`os.Logger` の category `appearance` に info ログが出ます）。

---

## 2. `dialogue.json`

### 場所

- 同梱: `Sources/Enoki/Resources/DialogueText/dialogue.json`
- 差し替え: 使用中スキンフォルダ直下の `dialogue.json`

### 構造

同梱のデモ（1 人用）はこの形です。

```json
{
  "schema_version": 1,
  "speakers": [
    { "id": "shiori", "displayName": "栞" }
  ],
  "dialogues": [
    {
      "id": "work_001",
      "category": "work",
      "cooldown": 3600,
      "lines": [
        { "speaker": "shiori", "text": "そろそろ、続きに戻りましょうか" }
      ]
    },
    {
      "id": "encouragement_003",
      "category": "encouragement",
      "cooldown": 7200,
      "lines": [
        { "speaker": "shiori", "text": "うまくいかない日もあります" },
        { "speaker": "shiori", "text": "それでも、座っているだけで十分です" }
      ]
    }
  ]
}
```

2 人以上で掛け合いをさせるなら、`speakers` に人数ぶん並べて、`lines` で話者を切り替えます。

```json
{
  "schema_version": 1,
  "speakers": [
    { "id": "mike", "displayName": "ミケ" },
    { "id": "kuro", "displayName": "クロ" }
  ],
  "dialogues": [
    {
      "id": "pair_001",
      "category": "pair",
      "cooldown": 5400,
      "lines": [
        { "speaker": "mike", "text": "ちゃんと休んでる？" },
        { "speaker": "kuro", "text": "……あとで" },
        { "speaker": "mike", "text": "いまだよ" }
      ]
    }
  ]
}
```

### フィールド

ルート:

| キー | 必須 | 意味 |
|---|---|---|
| `schema_version` | 任意 | 省略時 1。現在の実装では読み込むだけで分岐に使っていません |
| `speakers` | 任意 | 話者の宣言（下記）。省略すると `lines` に出てきた id から自動で決まります |
| `dialogues` | 必須 | 会話の配列。無ければ 0 件として扱われます |

#### `speakers`（話者の宣言）

| キー | 必須 | 意味 |
|---|---|---|
| `id` | **必須** | `lines` の `speaker` と突き合わせる文字列。自分のキャラクター名でかまいません |
| `displayName` | 任意 | 吹き出しの上に出す名前（省略時は `id` をそのまま表示） |
| `anchor` | 任意 | 吹き出しのしっぽの横位置。`0` = 左端 / `0.5` = 中央 / `1` = 右端 |

- **`anchor` を省略すると人数から自動で決まります**: **1 人なら中央 (0.5)**、2 人なら 0.25 / 0.75、
  3 人以上なら等間隔。**1 人用の台詞ファイルは何も指定しなくても吹き出しが中央に出ます。**
- 並べた順が立ち位置（左→右）と名前ラベルの色の順になります。
- `speakers` を**書いた場合**、`lines` の `speaker` は宣言した id だけが有効です
  （打ち間違いで知らない話者が増えるのを防ぐため、その会話は読み飛ばされます）。
- `speakers` を**書かなかった場合**は、`lines` に出てきた id がそのまま話者になります
  （名前は id そのまま、立ち位置は登場順と人数から自動）。
- 2 人以上にするときの絵と `anchor` の合わせ方は 5 章「キャラクターを増やす（1 人 → 2 人以上）」へ。

`dialogues[]` の 1 項目 = **1 会話**（最大 4 発言の一続きのやりとり）:

| キー | 必須 | 意味 |
|---|---|---|
| `id` | **必須** | 一意な文字列。重複した会話は捨てられます。履歴とクールダウンの単位 |
| `category` | **必須** | 下表の値のどれか。未知の値だとその会話だけ捨てられます |
| `cooldown` | 任意 | 同じ会話を再び選べるまでの秒数。省略時 **3600**（1 時間） |
| `lines` | **必須** | 発言の配列。空だとその会話は捨てられます |
| `profiles` | 任意 | この会話を使ってよい見た目プロファイル id の配列。省略 = 全プロファイル共通 |

`lines[]` の 1 項目 = **1 発言**:

| キー | 必須 | 意味 |
|---|---|---|
| `speaker` | **必須** | 話者の id。**任意の文字列**（`speakers` を宣言した場合はその id のいずれか）。空文字は不可 |
| `text` | **必須** | 台詞。空白のみは不可 |
| `reaction` | 任意 | この発言に合わせて 1 回再生するアニメーション名。スキンに同名のアニメーションが**あるときだけ**再生されます（同梱の台詞では未使用） |

### category（`DialogueCategory`）

現在コードに定義されている値です（`Sources/EnokiCore/Dialogue/DialogueModels.swift`）。
**この 11 種類以外は書けません**（未知の値の会話は読み飛ばされます）。

| category | 使われ方 |
|---|---|
| `work` | 仕事に戻る声かけ。休憩・昼食のあと 10〜15 分で出る |
| `water` | 水分（約 2 時間おき） |
| `break` | 休憩（50〜60 分おき） |
| `lunch` | 昼食（11:30〜14:00 の窓、12:00 目標） |
| `encouragement` | 励まし（13:00〜18:00 の窓、90 分前後おき） |
| `ambient` | 独り言・雰囲気（40〜90 分おき） |
| `pair` | 2 人以上のやりとり（`ambient` と同じ周期）。1 人用の台詞ファイルでは使わなくて構いません |
| `renofa` / `renofa_pre_match` / `renofa_match` / `renofa_post_match` | **特定イベント日（custom event）用**のカテゴリ。イベント当日だけ、かつプロファイルが許可したときだけ候補に入る。後ろ 3 つは「イベント開始前・進行中・終了後」の局面に対応する |

自分のキャラクター向けに使うなら、まず `work` / `water` / `break` / `lunch` /
`encouragement` / `ambient` の 6 つを埋めれば十分です（同梱のデモもこの 6 つ × 5 件）。
掛け合いをさせるなら `pair` も足します。
イベント用の 4 カテゴリは、7 章「Appearance / 特定イベント日の差分」 で使います。

**カテゴリ名そのものを増やしたい場合は Swift の enum に case を足す必要があります**
（`DialogueCategory`）。JSON だけでは増やせません。

### 書くときの注意

- **文字コードは UTF-8**（BOM なし）。日本語をエスケープする必要はありません。
- **厳密な JSON** です。コメント（`//`）も末尾カンマも書けません。
- 1 会話の発言は **4 つまで**を目安にしてください。ローダ側の上限ではありませんが、発言は 1 つずつ
  順番に吹き出しに出る（1 行あたり 3〜7 秒 + 間）ので、長いと間延びします。同梱ファイルは検証テストで
  4 発言までに制限しています。
- ローダは**壊れた会話だけを捨てて残りを読みます**。ファイル全体が無効になることはありません
  （ただし JSON として壊れていると全部読めません）。捨てた理由は `os.Logger`
  （category `conversation`）に出ます。
- 保存したら `python3 -m json.tool <file>` で構文を確認しておくと安全です。

### 同梱ファイルを直接編集する場合（方法 B）

`Tests/EnokiCoreTests/DialogueLoaderTests.swift` が同梱 `dialogue.json` の
**件数（6 カテゴリ × 5 件）・話者が 1 人であること・id の一意性・1 会話 4 発言まで**を検証しています。
同梱ファイルを書き換えると `make test` が失敗するので、テストの期待値も一緒に直してください
（自分のフォルダに `dialogue.json` を置く方法 A なら、テストは触らなくて済みます）。

---

## 3. スプライトシート

### 形式（Codex Pet 形式・非公式互換）

同梱アセットはこの形式です。フォルダに `pet.json` と画像を 1 枚置きます。

> **Codex Pet のアセット形式と非公式に互換です。** 同じ形式のフォルダをそのまま読み込めるようにしてあり、
> `~/.codex/pets/` 配下も探索先のひとつにしています。
> **Enoki は OpenAI とは無関係で、OpenAI による承認・提携・推奨を受けたものではありません。**
> 互換性は非公式なもので、先方の仕様変更で動かなくなる可能性があります。
> このリポジトリには Codex / OpenAI 由来の公式アセットを含めていません。

```
my_pet/
  pet.json
  spritesheet.png
  dialogue.json   ← 置けば台詞も差し替えられる（任意）
```

```json
{
  "id": "my_pet",
  "displayName": "わたしのキャラクター",
  "description": "自由記述",
  "spritesheetPath": "spritesheet.png"
}
```

（`Sources/Enoki/Resources/DefaultSkin/pet.json` と同じ形です）

| 項目 | 値 |
|---|---|
| 画像形式 | **PNG**（WebP・JPEG も ImageIO 経由で読めますが、透過が要るので PNG 推奨） |
| 背景 | **完全な透過**（アルファ）。不透明ピクセルはクリック判定にも使われます |
| グリッド | **8 列 × 9 行** |
| 1 コマ | **192 × 208 px** |
| 画像全体 | **1536 × 1872 px**（同梱のデモもこのサイズ） |
| 解像度 | 1x（`mascot.pixelScale` を `2` にすれば 2x 素材として扱えます） |

`spritesheetPath` を省略しても `spritesheet.png` → `spritesheet.webp` の順に探します。
`pet.json` に `mascot.grid` を書けば別のグリッドにもできます
（未指定なら画像サイズから 8×9 のセルサイズを推定）。
`mascot.animations` / `mascot.states` でコマ割りや状態の割り当ても変えられます
（詳細は [architecture.md](architecture.md) の §6.2）。

### 行（row）と状態の対応

`CodexPetDefaults.rowSpecs` が決めている既定の割り当てです。
**この並びに合わせて描けば `pet.json` にアニメーション定義を書く必要はありません。**

| 行 | アニメーション名 | 使うコマ（列） | いつ出るか |
|---|---|---|---|
| 0 | `idle` | 0–5 | 待機（既定の表示） |
| 1 | `running-right` | 0–7 | ドラッグ中 |
| 2 | `running-left` | 0–7 | 現在は未使用（ドラッグ方向の判定をしていないため） |
| 3 | `waving` | 0–3 | クリックしたときのリアクション |
| 4 | `jumping` | 0–4 | クリックしたときのリアクション |
| 5 | `failed` | 0–7 | 既定の状態遷移では未使用（`reaction` から呼べます） |
| 6 | `waiting` → `sleep` | 0–5（`sleep` は列 4–5） | 無操作が続いたときの導入 → 寝息ループ |
| 7 | `running` | 0–5 | 待機のバリエーション（`idle` プールの 1 つ） |
| 8 | `review` | 0–5 | 待機のバリエーション（`idle` プールの 1 つ） |

- 行の**末尾が透明なコマは自動的に再生から外れます**。6 コマ描けない行は、左詰めで描けば足ります。
- 画像が 8×9 のグリッドに収まっていれば、描いていない行が透明のままでも**読み込みは成功します**
  （その行が再生されたときに何も映らないだけです）。既定の状態遷移で実際に使われるのは
  行 0・7・8（待機）、行 1（ドラッグ）、行 3・4（クリック時のリアクション）、行 6（居眠り）です。
  最低限この 7 行を描いてください。

### 1 枚のスプライトに何人まで描けるか

アプリは**スプライトシート 1 枚・ウィンドウ 1 つ**しか扱いません（1 プロセス 1 体）。
1 コマの中に 2 人並べて描けば「2 人組」に見えますが、アプリが 2 体として管理するわけではありません。
同梱のデモ（栞）は**セルの中央に 1 人**が立っている形です。

- 誰が話しているかは**吹き出しの位置と名前**だけで表します。しっぽの向きは
  `dialogue.json` の `speakers`（またはその人数）で決まります → 2 章の `speakers`。
- **1 人のキャラクターなら何も指定しなくて構いません。** 話者が 1 人の台詞ファイルでは、
  吹き出しは自動的に**中央**に出ます。
- **2 人以上にする場合**は、セルの広げ方・立ち位置の合わせ方・台詞の書き方をまとめて
  5 章「キャラクターを増やす（1 人 → 2 人以上）」に書いています。

### 差分どうしで位置を揃える（重要）

見た目プロファイルを切り替えると、**同じウィンドウのままスプライトシートだけが入れ替わります**。
差分ごとにキャラクターの大きさや立ち位置がずれていると、着替えのたびに絵が跳ねます。

各差分で次を揃えてください。

- **キャンバス（1 コマ）のサイズ**: 192 × 208 px
- **足元の基準線**: キャラクターの足がセル下端から同じ位置に来るようにする
  （同梱素材の生成スクリプトは**下端から 2px** に足元を合わせています）
- **水平の基準位置**: キャラクター（2 人なら 2 人の中心）をセルの中央に置く
- **身長**: 差分間で同じ。差分を作るときは、元になるセットの `idle` のコマに高さを合わせます

小物（旗・カバンなど）がセルからはみ出すと端が切れます。はみ出す前提で描かないでください。

### もう 1 つの形式（ストリップ）

`pet.json` が無く `manifest.json` があるフォルダは、「1 アニメーション = 1 枚の横並び画像」
として読まれます。1 枚のシートを作るのが難しい場合はこちらでも構いません
（→ [architecture.md](architecture.md) の §6.3）。

### 生成スクリプト（ポーズ画像 → アトラス）

**ポーズごとに 1 枚ずつ画像がある場合は、`scripts/build_atlas.py` で 1 枚のシートに詰められます。**
同梱のデモも、ポーズ画像 24 枚からこのスクリプトで作っています。

```bash
pip3 install pillow numpy
python3 scripts/build_atlas.py --src ~/Desktop/my_poses --out ~/.codex/pets/my_pet \
    --id my_pet --name "わたしのキャラクター"
```

`--out` に `pet.json` と `spritesheet.png` を書き出します。そのまま
`ENOKI_SKIN_DIR=~/.codex/pets/my_pet swift run Enoki` で試せます。

- **描き直しはしません**（切り出し・縮小・配置のみ）。
- **全コマ共通の切り出し範囲と縮小率**を使うので、どのコマでも身長と立ち位置が揃います。
  足元はセル下端から 2px、水平は中央（→ 3 章「差分どうしで位置を揃える」の条件を自動で満たします）。
- 足りないポーズは**他の絵で埋める**ので、数枚しか無くても動くセットになります
  （埋めたぶんはログに出ます）。

#### ファイル名（既定のポーズ名）

既定では次の名前を探します（拡張子は `.png` / `.webp` / `.jpg`）。

| 行 | アニメーション | 探すポーズ名 |
|---|---|---|
| 0 | `idle` | `normal`, `wink_1`, `wink_2` |
| 1・2 | `running-right` / `running-left` | `drag`, `look_right`, `look_left` |
| 3 | `waving` | `touch`, `wave_1`, `wave_2` |
| 4 | `jumping` | `look_top`, `jump`, `success_1`, `success_2` |
| 5 | `failed` | `failure_1`, `failure_2` |
| 6 | `waiting` / `sleep` | `waiting_1`, `waiting_2`, `sleep_1`, `sleep_2` |
| 7 | `running` | `work_1`, `work_2`, `work_3` |
| 8 | `review` | `review`, `review_2` |

別の名前を使っているなら `--map` に対応表を渡します（書かなかった行は既定のまま）。

```json
{
  "fallback": "stand",
  "rows": {
    "idle":    ["stand", "stand", "blink", "stand"],
    "waving":  ["hello_1", "hello_2"],
    "waiting": ["stand", "stand", "zzz", "zzz"]
  }
}
```

```bash
python3 scripts/build_atlas.py --src ~/Desktop/my_poses --out ~/.codex/pets/my_pet --map map.json
```

#### そのほかのオプション

| オプション | 意味 |
|---|---|
| `--cell 320x208` | 1 コマの大きさ。**2 人以上を入れるとき**に横へ広げる（`pet.json` に `mascot.grid` も書き出します）→ 5 章 |
| `--pad 2` | セル内の余白 px（足元の位置） |
| `--description` | `pet.json` の説明文 |
| `--webp` | `spritesheet.webp` も書き出す |
| `--qa` | `qa/contact-sheet.png`（行・コマのラベル付き一覧）と `qa/row-map.json` を書き出す |

2 人以上が写っていると、**吹き出しの `anchor` の目安も推定して表示します**（5 章）。

> `scripts/build_variant_atlas.py` のほうは、開発者の差分素材（4×2 のシート 2 枚 + idle 1 枚）
> 専用の古いスクリプトです。ポーズが 1 枚ずつある場合は `build_atlas.py` を使ってください。

---

## 4. 最短で自分のキャラクターに置き換える

ビルドし直さない方法（A）の手順です。

1. **スプライトシートを用意する**
   8 列 × 9 行・1 コマ 192×208px・全体 1536×1872px の透過 PNG を作る。
   最低限、行 0・7・8（待機）、行 1（ドラッグ）、行 3・4（リアクション）、行 6（居眠り）を埋める。

   ポーズごとに画像が分かれているなら、`scripts/build_atlas.py` が 1 枚に詰めてくれます
   （→ 3 章「生成スクリプト」）。この場合は次の手順 2 も一緒に済みます。

   ```bash
   python3 scripts/build_atlas.py --src ~/Desktop/my_poses --out ~/.codex/pets/my_pet \
       --id my_pet --name "わたしのキャラクター"
   ```

2. **フォルダを作って置く**

   ```bash
   mkdir -p ~/.codex/pets/my_pet
   cp spritesheet.png ~/.codex/pets/my_pet/
   cat > ~/.codex/pets/my_pet/pet.json <<'JSON'
   {"id": "my_pet", "displayName": "わたしのキャラクター", "spritesheetPath": "spritesheet.png"}
   JSON
   ```

3. **台詞を書く**
   `~/.codex/pets/my_pet/dialogue.json` を作る。`speaker` は**自分のキャラクターの id**、
   `category` は 2 章の category の表の値から選ぶ。まずは 1 件でも動きます。

   ```json
   {
     "schema_version": 1,
     "speakers": [
       { "id": "mike", "displayName": "ミケ" }
     ],
     "dialogues": [
       { "id": "hello_001", "category": "ambient",
         "lines": [{ "speaker": "mike", "text": "こんにちは" }] }
     ]
   }
   ```

   話者が 1 人なら吹き出しは中央に出ます。`speakers` を省略しても動きますが、
   その場合は `id` がそのまま名前として表示されます。

4. **起動して選ぶ**

   ```bash
   make run                       # build/Enoki.app を作って起動
   ```

   メニューバーのアイコン → 「スキン」→ 一覧に出る `my_pet` を選ぶ
   （`~/.codex/pets` 直下は自動で一覧に出ます。別の場所なら「フォルダを選択…」）。

   開発中は環境変数でも指定できます。

   ```bash
   ENOKI_SKIN_DIR=~/.codex/pets/my_pet swift run Enoki
   ```

5. **台詞を確かめる**

   ```bash
   # 起動 2 秒後に 1 回しゃべらせる
   ENOKI_DEBUG_SPEAK_ON_LAUNCH=1 ./build/Enoki.app/Contents/MacOS/Enoki
   # 会話 id を指定してしゃべらせる
   ENOKI_DEBUG_SPEAK_ON_LAUNCH=1 ENOKI_DEBUG_SPEAK_ID=hello_001 ./build/Enoki.app/Contents/MacOS/Enoki
   ```

   メニューの「ちょっと話して」でも 1 回しゃべります。読み飛ばされた台詞があるかはログで確認します。

   ```bash
   log show --style compact --info --last 5m \
     --predicate 'subsystem == "com.enoki.mascot" AND category == "conversation"'
   ```

配布用に自分のキャラクター版をビルドしたい場合（B）は、`Sources/Enoki/Resources/DefaultSkin/`
と `Sources/Enoki/Resources/DialogueText/dialogue.json` を差し替えて `make app` します。
その際は `DialogueLoaderTests` の期待値も直してください。

**2 人以上にしたい場合**は、続けて 5 章「キャラクターを増やす（1 人 → 2 人以上）」を読んでください。

---

## 5. キャラクターを増やす（1 人 → 2 人以上）

同梱のデモは 1 人ですが、2 人以上に増やせます。やることは
**(1) 1 枚の絵に全員を描く**、**(2) `dialogue.json` の `speakers` を絵の立ち位置に合わせる** の 2 つです。

### 5.1 前提: 1 プロセス = スプライト 1 枚 = ウィンドウ 1 つ

アプリは**1 枚のスプライトシートを 1 つの窓に表示するだけ**で、複数体を別々に動かす仕組みはありません。
2 人組に見せるには、**同じコマの中に 2 人を描きます**（同梱の朔と栞のセットもそうでした）。

そのため、次のことは**絵の側で表現する**ことになります。

- 片方だけ手を振る / 片方だけ居眠りする → そういうコマを描く（アニメーションは 1 種類ずつ）
- クリックのリアクションは**全員に同時**に起きます（誰をクリックしたかは区別しません）
- 立ち位置の入れ替え・片方だけ退場 → できません

### 5.2 セルの大きさを決める

2 人以上を 1 コマに入れるには、次の 2 つのどちらかです。

| やり方 | 1 コマ | 画像全体（8 列 × 9 行） | 向いている場面 |
|---|---|---|---|
| **A. そのまま詰める** | 192 × 208 px | 1536 × 1872 px | 手軽。1 人あたりは小さくなる |
| **B. セルを広げる** | 例 320 × 208 px | 例 2560 × 1872 px | 横に余裕が要るとき。**窓もその幅になる** |

B の場合は `pet.json` に `mascot.grid` を書きます。

```json
{
  "id": "my_duo",
  "displayName": "ふたり",
  "spritesheetPath": "spritesheet.png",
  "mascot": {
    "grid": { "columns": 8, "rows": 9, "cellWidth": 320, "cellHeight": 208 }
  }
}
```

- 画像は **列数 × `cellWidth`**、**行数 × `cellHeight`** 以上の大きさが必要です（足りないと読み込みエラー）。
- **セルの大きさがそのまま窓の大きさ**になります（1x 素材の場合）。メニューの「表示倍率」で拡大縮小できます。
- 行と状態の対応（3 章の表）は変わりません。列（コマ数）も同じです。

ポーズ画像から作るなら、`scripts/build_atlas.py` に `--cell` を渡すだけです
（`mascot.grid` 付きの `pet.json` も書き出されます）。

```bash
python3 scripts/build_atlas.py --src ~/Desktop/duo_poses --out ~/.codex/pets/my_duo \
    --cell 320x208 --id my_duo --name "ふたり"
```

### 5.3 全コマで立ち位置を揃える

3 章の注意点が、人数が増えるとさらに効いてきます。

- **各キャラの水平位置を全コマで同じに**する（左の子は、どのコマでも同じ位置に立つ）
- **足元の基準線を全員・全コマで揃える**（同梱デモはセル下端から 2px）
- セルからはみ出した部分は切れます

ここがずれると、待機 → 手を振る → 居眠り と切り替わるたびに人が横に跳ねます。

**ポーズ画像 1 枚ずつから `scripts/build_atlas.py` で作れば、ここは自動で揃います**
（全コマに同じ切り出し範囲と縮小率を使い、足元と水平中心を固定して配置するため）。
元画像の側で 2 人の立ち位置を揃えておけば、アトラス上でも揃ったままになります。

### 5.4 `dialogue.json` に人数ぶんの `speakers` を書く

吹き出しのしっぽは `anchor`（0 = 左端, 1 = 右端）の位置に出ます。
**絵の中でそのキャラの中心がどこにあるかを、セル幅に対する比で書きます。**

> 例: セル幅 320px で、左の子の中心が 96px の位置 → `96 ÷ 320 = 0.30`

`scripts/build_atlas.py` は、1 コマに複数人が写っていると**この値を推定して表示します**。
そのまま `dialogue.json` に貼れる形で出るので、細かく測る必要はありません。

```
-- 1 コマに 2 人ぶんのかたまりが見えます。dialogue.json の speakers の目安:
{
  "speakers": [
    { "id": "speaker1", "displayName": "話者1", "anchor": 0.3 },
    { "id": "speaker2", "displayName": "話者2", "anchor": 0.697 }
  ]
}
```

```json
{
  "schema_version": 1,
  "speakers": [
    { "id": "mike", "displayName": "ミケ", "anchor": 0.30 },
    { "id": "kuro", "displayName": "クロ", "anchor": 0.70 }
  ],
  "dialogues": [
    {
      "id": "pair_001",
      "category": "pair",
      "cooldown": 5400,
      "lines": [
        { "speaker": "mike", "text": "ちゃんと休んでる？" },
        { "speaker": "kuro", "text": "……あとで" }
      ]
    }
  ]
}
```

- `anchor` を**省略すると人数から自動**で決まります（2 人 → 0.25 / 0.75、3 人以上 → 等間隔）。
  絵の立ち位置がそれに近いなら書かなくて構いません。
- 名前ラベルの色は `speakers` に並べた順です（紺 → 赤茶 → 緑 → 紫）。
- 掛け合いは `pair` カテゴリに書きます。1 会話 4 発言までが目安です。
- **吹き出しは常に 1 つずつ**表示されます。2 人が同時にしゃべることはなく、1 行ずつ順番に出ます。
- 1 人用の台詞ファイルから増やす場合、既存の台詞（`work` や `ambient`）は**そのままで動きます**。
  増えた側の台詞を足し、掛け合いを `pair` に書き足していくのが楽です。

### 5.5 プロファイルごとに人数を変える

**スプライトセットのフォルダに `dialogue.json` を置くと、そのプロファイルのときだけその台詞が使われます**
（プロファイルを切り替えると台詞も読み直します）。

```
~/.codex/pets/my_duo/         ← casual プロファイル用（2 人）
  pet.json
  spritesheet.png
  dialogue.json               ← speakers 2 人ぶん + pair の掛け合い
```

平日は 1 人（ベーススキン）、休日は 2 人（`casual` のスプライトセット）といった構成もできます。
プロファイルの足し方は 7 章を参照してください。

### 5.6 確認する

```bash
# 2 人組のフォルダを直接指定して起動し、掛け合いを 1 回再生する
ENOKI_SKIN_DIR=~/.codex/pets/my_duo \
  ENOKI_DEBUG_SPEAK_ON_LAUNCH=1 ENOKI_DEBUG_SPEAK_ID=pair_001 \
  ./build/Enoki.app/Contents/MacOS/Enoki
```

ログには話者ごとに 1 行ずつ出ます。`frame` の x と `tailX` を足した値がしっぽの位置なので、
**2 人で値が変わっていれば** `anchor` が効いています。

```bash
log show --style compact --info --last 5m \
  --predicate 'subsystem == "com.enoki.mascot" AND (category == "conversation" OR category == "bubble")'
```

読み込みログの `話者: mike, kuro` が宣言どおりか、`（1人用）` が付いていないかも確認できます。

---

## 6. キャラクター名・speaker ID の扱い（コード変更が必要な箇所）

**データだけで差し替えられない部分が残っています。** 正直に書くと、現状は次のとおりです。

| 変えたいもの | データだけで変えられるか | 変える場所 |
|---|---|---|
| 立ち絵・衣装 | **できる** | スプライトシート |
| 台詞の内容 | **できる** | `dialogue.json` |
| スキンの表示名 | **できる** | `pet.json` の `displayName` |
| 話者の id（`speaker` の値） | **できる** | `dialogue.json` の `speakers` / `lines` |
| 吹き出しに出る話者名 | **できる** | `dialogue.json` の `speakers[].displayName` |
| 吹き出しのしっぽの左右位置 | **できる** | `dialogue.json` の `speakers[].anchor`（省略時は人数から自動） |
| 話者の人数（1 人 / 2 人 / 3 人以上） | **できる** | `dialogue.json` の `speakers` |
| 話者名の文字色 | できない | `SpeechBubbleView` のパレット（登場順に 4 色。`Sources/Enoki/Dialogue/SpeechBubbleView.swift`） |
| メニュー・About の「朔と栞」表記 | できない | `StatusMenuController` / `AppDelegate` / `Resources/Info.plist` |
| 既定で探すフォルダ名 `~/.codex/pets/sakushio_pet` | できない | `SkinLoader.defaultCodexPetURL` |
| 台詞カテゴリの名前を増やす | できない | `DialogueCategory` enum |

つまり、**台詞・スプライト・話者（名前と立ち位置）はデータだけで差し替えられます**。
コード変更が要るのは、アプリ自体の名前・既定フォルダ名・台詞カテゴリの追加といった部分だけです。
なお `saku` / `shiori` という id には、宣言を省略したときの既定表示名（朔 / 栞）が
互換のため残っています。別のキャラクターに使うときは `speakers` で `displayName` を指定してください。

---

## 7. Appearance / 特定イベント日の差分

「いまどんな見た目で、どんな話をするか」をまとめた設定が**見た目プロファイル**です。
定義は `Sources/Enoki/Resources/Profiles/profiles.json` にあり、プロファイルを増やすのに
**Swift の変更は要りません**。ただし解決ロジックだけは一部の id を名前で参照しています
（`AppearanceResolver` が `default` / `work` / `casual`、`DayProfileResolver` の日付ルールが `renofa`）。

### 現在リポジトリに入っているプロファイル

| id | displayName | `spriteSet` | 備考 |
|---|---|---|---|
| `default` | Default | なし（ベーススキン） | 最後の受け皿。メニューの「自動に戻す」もここ |
| `work` | Work | なし（ベーススキン） | 仕事中モード ON のとき |
| `casual` | Casual | `saku_shiori_casual`（**同梱していない**） | 仕事中モード OFF・土日・祝日。`work` カテゴリを落とす |
| `renofa` | Renofa | `saku_shiori_renofa` ほか（**同梱していない**） | 特定イベント日用のサンプル。開始前・進行中・終了後の局面ごとに別セットを割り当てる例 |

**スプライトセットはどれも同梱していません。** `casual` / `renofa` は開発者個人の設定が
定義として残っているもので、素材が見つからなければ**ベーススキン（同梱のデモ）にフォールバック**し、
台詞のカテゴリ制限だけが効きます。自分用の差分を作るときのひな型として読んでください
（`renofa` は特に、第三者のロゴ・商標を含む素材を配布しないためリポジトリに入れていません）。

### プロファイルを足す

`profiles.json` に 1 項目足すだけです。Swift の変更は不要で、メニューの
「見た目 (Appearance)」と「起動時のプロファイル」に自動で並びます。

```json
{
  "id": "special_event",
  "displayName": "Special Event",
  "spriteSet": "my_pet_special",
  "dialogueCategories": ["ambient", "pair", "encouragement"],
  "disabledDialogueCategories": ["work"],
  "special": true
}
```

| キー | 意味 |
|---|---|
| `id` | プロファイル id。`dialogue.json` の `profiles` から参照する名前 |
| `displayName` | メニューの表示名（省略時は id） |
| `spriteSet` | 使うスプライトセットの**フォルダ名**。`null` / 省略ならベーススキン |
| `spriteSetsByPhase` | イベント当日の局面（`matchDay` / `preMatch` / `inMatch` / `postMatch`）ごとのフォルダ名 |
| `dialogueCategories` | 使ってよいカテゴリ（省略 = 制限しない） |
| `disabledDialogueCategories` | 使わないカテゴリ。`dialogueCategories` より強い |
| `special` | `true` なら、仕事中モードを切り替えても手動選択が解除されない |
| `transitionAnimation` | 着替え後に 1 回だけ再生するアニメーション名（スキンに無ければ無視） |

スプライトセットは `~/.codex/pets/my_pet_special/` などに、
**ベーススキンと同じ形式**（`pet.json` + スプライトシート）で置きます。

足しただけのプロファイルは、**メニューから手動で選んだときだけ**使われます
（手動選択はその日限りで、日付が変わると自動に戻ります）。「毎年この日は自動でこの見た目」に
したい場合は、下の「どのプロファイルが選ばれるか」にある日付ルールを Swift 側に足します。

### プロファイル専用の台詞

`dialogue.json` の会話に `profiles` を書くと、そのプロファイルのときだけ候補になります。
同梱のデモには入っていませんが、プロファイルを足したときはこの形で専用の台詞を書きます。

```json
{
  "id": "special_001",
  "category": "pair",
  "cooldown": 3600,
  "profiles": ["special_event"],
  "lines": [
    { "speaker": "saku",   "text": "今日は特別な日だね" },
    { "speaker": "shiori", "text": "はい。楽しみましょう" }
  ]
}
```

### どのプロファイルが選ばれるか

優先順（`AppearanceResolver.resolve`）:

1. メニューで手動選択したプロファイル（**その日限り**。日付が変わると自動へ戻る）
2. その日の自動判定（`DayProfileResolver`。イベント日 → `renofa` / 土日・祝日 → `casual`）
3. 「仕事中モードと連動して切り替え」が ON なら、仕事中 → `work` / それ以外 → `casual`
4. `default`

日付ベースの判定ルール（曜日・祝日・イベント日）を増やすときは、
`Sources/EnokiCore/Appearance/DayProfileResolver.swift` の `rules` に `DayRule` を 1 つ足します。
ここは JSON ではなく Swift です。

### イベント日の局面（時刻ベース）

イベント日は、開始時刻を基準に「開始前 → 進行中 → 終了後」と局面が変わり、
`spriteSetsByPhase` があればスプライトも、対応する台詞カテゴリも切り替わります。
時刻の情報は `~/Library/Application Support/Enoki/renofa-schedule.json`
（または `Sources/Enoki/Resources/Schedule/renofa-schedule.json`）から読みます。

**この日程データはリポジトリに含めていません。** 個人データとして各自で置く前提です
（形式と置き場所は `Sources/Enoki/Resources/Schedule/README.md`。`.gitignore` 済みなので
リポジトリの中に置いてもコミットされません）。置いていなければイベント日の判定は行われず、
曜日と祝日だけで見た目が決まります。

**アプリはネットワークに一切アクセスしません。** 予定データはローカルの JSON だけが情報源です。
仕組みの詳細は [architecture.md](architecture.md) の §12.9 を参照してください。

---

## 8. うまくいかないときは

| 症状 | 見るところ |
|---|---|
| キャラクターが変わらない | メニュー「スキン」の「現在:」表示でどのフォルダを読んでいるか確認。「再読み込み」を押す |
| スプライトが崩れる / コマがずれる | 画像サイズが 1536×1872（8×9 × 192×208）になっているか。`pet.json` の `mascot.grid` で明示もできる |
| 着替えると位置が跳ねる | 差分どうしで足元・水平中心・身長が揃っていない（→ 3 章「差分どうしで位置を揃える」） |
| 台詞が出ない | `dialogue.json` が JSON として壊れていないか（`python3 -m json.tool`）。`speaker` / `category` が既知の値か。ログ（category `conversation`）に読み飛ばしの理由が出ます |
| 台詞が一部しか出ない | 仕事中モード・Quiet Mode・プロファイルのカテゴリ制限で絞られている可能性。メニューの「会話」「見た目 (Appearance)」を確認 |
| プロファイルを足したのに見た目が変わらない | `spriteSet` のフォルダ名が実際のフォルダと一致しているか。見つからないとベーススキンにフォールバックします（ログ category `appearance`） |

ログはまとめてこれで見られます。

```bash
log show --style compact --info --last 10m --predicate 'subsystem == "com.enoki.mascot"'
```
