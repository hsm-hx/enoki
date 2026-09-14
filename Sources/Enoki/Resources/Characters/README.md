# 内蔵スプライトセット置き場（現在は空です）

見た目プロファイル（`Resources/Profiles/profiles.json` の `spriteSet`）が探すフォルダのうち、
**アプリに同梱する**ぶんをここに置きます。1 スプライトセット = 1 フォルダで、
中身はベーススキンと同じ形式（`pet.json` + スプライトシート、または `manifest.json` + ストリップ）です。

```
Resources/Characters/
  <spriteSet 名>/
    pet.json
    spritesheet.png
```

**このリポジトリには同梱しているスプライトセットがありません。**
`profiles.json` の `casual` / `renofa` が参照する朔と栞のセットは、開発者個人のアセット
（および第三者のロゴ・商標を含む素材）なので配布していません。

スプライトセットの探索順（先に見つかったものを使います）:

1. `~/.codex/pets/<spriteSet>/`
2. `~/Library/Application Support/Enoki/Characters/<spriteSet>/`
3. ここ（アプリ内蔵 `Resources/Characters/<spriteSet>/`）

どこにも無い／読めない場合は、スキンメニューで選んでいる **ベーススキンにフォールバック** します
（マスコットは普通に動き、`os.Logger` の `appearance` カテゴリに info ログが出ます）。
同梱のベーススキンはデモ用キャラクター「栞」（`Resources/DefaultSkin/`）です。

自分のスプライトセットを追加する手順は [docs/customization.md](../../../../docs/customization.md) を参照してください。

> このファイルは、SwiftPM が空フォルダを扱えないためのプレースホルダも兼ねています。削除しないでください。
