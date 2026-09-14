# examples — 書き換えて使うサンプル

clone したあと、**どのファイルを書き換えれば自分のキャラクターを住まわせられるか**を、
実物を見ながら確かめるためのサンプルです。フォルダごとコピーして中身を書き換えてください。

```
examples/
  solo/                        1 人用のサンプル（pet.json + dialogue.json）
  duo/                         2 人用のサンプル（speakers を 2 人ぶん宣言）
  profiles.sample.json         見た目プロファイル（profiles.json）を増やす例
  build-atlas-map.sample.json  scripts/build_atlas.py の --map の例
```

手順とファイル仕様は [../docs/customization.md](../docs/customization.md) にまとまっています。
ここはその「動く実物」です。

---

## 使い方（1 人用）

サンプルにはスプライトシートを置いていません（画像はリポジトリに 1 つだけ持つ方針のため）。
**同梱のデモキャラクターのシートをコピーする**か、自分で用意した PNG を置いてください。

```bash
# 1. サンプルを自分の作業用フォルダにコピーする
cp -R examples/solo ~/.codex/pets/my-character

# 2. スプライトシートを置く（同梱デモを流用する場合）
cp Sources/Enoki/Resources/DefaultSkin/spritesheet.png ~/.codex/pets/my-character/

# 3. そのフォルダを指定して起動する
ENOKI_SKIN_DIR=~/.codex/pets/my-character swift run Enoki
```

`~/.codex/pets/` 配下に置くと、メニューバーの「スキン」からも選べるようになります。

あとは `pet.json`（名前）と `dialogue.json`（台詞）を書き換え、
スプライトシートを自分の絵に差し替えれば、自分のキャラクターになります。
スプライトの作り方（サイズ・透過・行の割り当て・生成スクリプト）は
[../docs/customization.md](../docs/customization.md) の 3 章を参照してください。

## 使い方（2 人用）

```bash
cp -R examples/duo ~/.codex/pets/my-duo
cp Sources/Enoki/Resources/DefaultSkin/spritesheet.png ~/.codex/pets/my-duo/
ENOKI_SKIN_DIR=~/.codex/pets/my-duo swift run Enoki
```

同梱デモのシートは 1 人しか描かれていないので、**吹き出しが左右に振り分けられる動き**だけを確認できます。
実際に 2 人を並べるときは、1 コマに 2 人描いたシートを用意し、必要なら `pet.json` に
`mascot.grid` を足してセルを広げます（→ customization.md の 5 章）。

```bash
# ポーズ画像から 2 人用のシートを作る例
python3 scripts/build_atlas.py --src ~/Desktop/duo_poses --out ~/.codex/pets/my-duo \
    --cell 320x208 --id my-duo --name "ふたり"
```

---

## `solo/dialogue.json` で分かること

| サンプル | 何を示しているか |
|---|---|
| `sample_ambient_001` | **通常の独り言**。`category: "ambient"` は 40〜90 分おきに出ます |
| `sample_lunch_001` | **時間帯で出る台詞**。`lunch` は 11:30〜14:00 の窓でだけ選ばれます（`encouragement` は 13:00〜18:00） |
| `sample_encouragement_001` | **1 会話に複数行**書いた例。1 行ずつ順に吹き出しへ出ます |
| `sample_work_001` | 仕事中モード（メニュー）が ON のときに出るカテゴリ |
| `sample_casual_001` | **状態差分**。`profiles: ["casual"]` を付けると、その見た目プロファイルのときだけ候補になります |

`speakers` を 1 人だけ宣言しているので、吹き出しは**中央**に出ます。
2 人以上にすると自動で左右に振り分けられます（`duo/dialogue.json`）。

> 台詞に書ける項目は `id` / `category` / `cooldown` / `profiles` / `lines`（`speaker` / `text` / `reaction`）だけです。
> 時刻そのものを条件に書く項目はありません。「朝だけ」のような出し分けは、
> カテゴリ（`lunch` など）と見た目プロファイル（曜日・祝日・イベント日で自動的に切り替わる）で表現します。

## `profiles.sample.json`

`Sources/Enoki/Resources/Profiles/profiles.json` に項目を足すときの例です。
このファイル自体はアプリから読まれません（コピー元としてだけ置いています）。

## アセットの扱い（重要）

`Sources/Enoki/Resources/DefaultSkin/` に入っているデモキャラクター **御影栞** のスプライトは、
**Enoki の公式デモキャラクター**であって、自由に使える素材ではありません。
自分の環境で Enoki を動かすために使うのは問題ありませんが、**再配布・商用利用・別作品への転用は
許諾していません**。条件は [../ASSETS_LICENSE.md](../ASSETS_LICENSE.md) を読んでください。

公開・配布するものを作る場合は、**自分で用意したスプライトに差し替えてください**。
このフォルダのサンプル（JSON）は Enoki のソースコードと同じ [MIT License](../LICENSE) です。
