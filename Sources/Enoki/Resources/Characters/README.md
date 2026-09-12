# 内蔵スプライトセット置き場

見た目プロファイル（`Resources/Profiles/profiles.json` の `spriteSet`）が探すフォルダのうち、
**アプリに同梱する** ぶんをここに置きます。1 スプライトセット = 1 フォルダで、
中身は既存のスキンと同じ形式（`pet.json` + スプライトシート、または `manifest.json` + ストリップ）です。

```
Resources/Characters/
  saku_shiori_casual/     ← 同梱（私服）。scripts/build_variant_atlas.py で生成
    pet.json
    spritesheet.png
```

スプライトセットの探索順（先に見つかったものを使う）:

1. `~/.codex/pets/<spriteSet>/`
2. `~/Library/Application Support/Enoki/Characters/<spriteSet>/`
3. ここ（アプリ内蔵 `Resources/Characters/<spriteSet>/`）

どこにも無い／読めない場合は、スキンメニューで選んでいる **ベーススキンにフォールバック** します
（マスコットは普通に動き、`os.Logger` の `appearance` カテゴリに info ログが出ます）。

同梱しているのは `saku_shiori_casual`（私服）だけです。`saku_shiori_renofa` は
ユーザーが自分で用意したローカル素材専用で、アプリには決して同梱しません
（クラブのロゴ・商標・選手名を含む素材を配布しないため）。
`~/Library/Application Support/Enoki/Characters/saku_shiori_renofa/` に置いてください。

> このファイルは、SwiftPM が空フォルダを扱えないためのプレースホルダも兼ねています。削除しないでください。
