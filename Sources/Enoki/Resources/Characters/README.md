# 内蔵スプライトセット置き場

見た目プロファイル（`Resources/Profiles/profiles.json` の `spriteSet`）が探すフォルダのうち、
**アプリに同梱する** ぶんをここに置きます。1 スプライトセット = 1 フォルダで、
中身は既存のスキンと同じ形式（`pet.json` + スプライトシート、または `manifest.json` + ストリップ）です。

```
Resources/Characters/
  saku_shiori_work/
    pet.json
    spritesheet.png
  saku_shiori_casual/
    manifest.json
    idle_1.png …
```

スプライトセットの探索順（先に見つかったものを使う）:

1. `~/.codex/pets/<spriteSet>/`
2. `~/Library/Application Support/Enoki/Characters/<spriteSet>/`
3. ここ（アプリ内蔵 `Resources/Characters/<spriteSet>/`）

どこにも無い／読めない場合は、スキンメニューで選んでいる **ベーススキンにフォールバック** します
（マスコットは普通に動き、`os.Logger` の `appearance` カテゴリに info ログが出ます）。

このリポジトリには**スプライトは同梱していません**。特に `saku_shiori_renofa` は
ユーザーが自分で用意したローカル素材専用で、アプリには決して同梱しません
（クラブのロゴ・商標・選手名を含む素材を配布しないため）。

> このファイルは、SwiftPM が空フォルダを扱えないためのプレースホルダも兼ねています。削除しないでください。
