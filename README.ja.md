<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Cubby のアプリアイコン">
</p>

<h1 align="center">Cubby</h1>

<p align="center">
  <b>コピーしたものすべてに、キーひとつで。</b><br>
  データが Mac の外に出ない、キーボード中心のネイティブ macOS クリップボードマネージャ。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="ライセンス: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 以降">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <b>日本語</b> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a>
</p>

```sh
brew install --cask no1coder/tap/cubby
```

または [Releases](https://github.com/no1coder/cubby/releases/latest) から公証済みの DMG をダウンロードしてください。macOS 14 以降が必要です（Apple シリコン / Intel 両対応）。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/panel-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/screenshots/panel-light.png">
    <img src="docs/assets/screenshots/panel-light.png" width="380" alt="テキスト、リンク、コード、カラー、ファイル、画像のカードが並ぶ Cubby のパネル">
  </picture>
</p>

Cubby はメニューバーに常駐し、コピーしたテキスト、リンク、コード、カラー、画像、ファイルを記憶します。<kbd>⇧⌘V</kbd> を押して数文字入力し、<kbd>↩</kbd> を押せば、直前に使っていたアプリにそのままペースト。マウスに触れる必要はありません。一日中コピー＆ペーストを繰り返す人（開発者、デザイナー、ライター、アドレスや定型文を使い回すすべての人）のための、速くてプライバシーを尊重するツールです。履歴は暗号化されて Mac の中にとどまります。Cubby がネットに接続するのは、新しいバージョンの確認（1 日 1 回、オフにも可能）と、自分で設定した言語モデルで翻訳するときだけです。

**主な機能**

- **すばやく検索してペースト。** リンク、コード、カラー、ファイルを種類ごとのカードで表示。画像内の文字まで検索でき、<kbd>↩</kbd> または <kbd>⌘1</kbd>〜<kbd>⌘9</kbd> でペーストできます。
- **好きなレイアウトで。** フローティングパネル、画面右端に固定するサイドバー、画面下端に並ぶカードのシェルフから選べます。<kbd>⌃⇧V</kbd> で画像だけのグリッドも開けます。
- **スクリーンショットと注釈。** <kbd>⇧⌘2</kbd> でウインドウや範囲をキャプチャし、注釈を付けて履歴に保存します。
- **物干しロープ。** 最大 12 枚の画像を画面上端に吊るしておき、必要なときにメニューバーから引き下ろせます。
- **アドレスガード。** コピーした暗号資産アドレスやカード番号がマルウェアにすり替えられると警告します。
- **macOS 26 で翻訳。** クリップボードの項目やスクリーンショットをその場で翻訳。デバイス上でも、自分で用意したモデルでも使えます。

## 動作の様子

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/search-paste.gif" alt="Shift-Command-V で Cubby のパネルを開き、数文字入力して履歴を絞り込み、Return で別のアプリにペーストする様子"><br>
      <sub><b>検索してペースト。</b>入力して探し、<kbd>↩</kbd> でペースト。</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/clothesline.gif" alt="メニューバーから下へドラッグして画像の物干しロープを引き下ろし、写真にポインタを重ね、1 枚をクリックして注釈を付ける様子"><br>
      <sub><b>物干しロープ。</b>メニューバーから下へドラッグして、吊るした画像を取り出せます。</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/screenshot-annotate.gif" alt="Shift-Command-2 でスクリーンショットを撮り、範囲を選択して枠・テキスト・矢印を加え、コピーする様子"><br>
      <sub><b>スクリーンショットと注釈。</b>撮って、描いて、ペースト。</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/address-guard.gif" alt="コピーした Ethereum アドレスがクリップボード内ですり替えられ、Cubby の警告が両方のアドレスを 1 文字ずつ比較し、違いを赤で示す様子"><br>
      <sub><b>アドレスガード。</b>すり替えられたアドレスをペースト前に検出します。</sub>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="2">
      <img src="docs/assets/gifs/screenshot-translate.gif" width="640" alt="スクリーンショット内の英語のウインドウ 2 つが行ごとにその場で中国語に翻訳され、仕切り線で原文と見比べる様子"><br>
      <sub><b>スクリーンショット翻訳（macOS 26）。</b> <kbd>⇧⌘T</kbd> で文字がその場で置き換わり、レイアウトはそのまま。仕切りをドラッグして原文と比較できます。</sub>
    </td>
  </tr>
</table>

## 機能

**記録と検索**

- テキスト（リッチテキストは RTF / HTML の書式を保持）、リンク、HEX カラー、画像、ファイルを記録します。同じものを再びコピーすると先頭に戻ります。お気に入りは期限切れになりません。それ以外は指定した件数（50〜2,000 件、デフォルトは 500 件）まで保持されます。
- カードは中身に合わせて表示されます。リンクはページタイトルと完全な URL、コードは言語名とシンタックスカラー、カラーは HEX と rgb() の値、画像は全体を表示。各カードにはコピー元のアプリ、時刻、<kbd>⌘</kbd> 番号が表示され、「今日」「昨日」「それ以前」にグループ分けされます。
- 入力を始めるだけで検索できます。すべての単語に一致する項目だけが表示され、一致箇所はハイライト、関連度の高い順に並び、カテゴリごとの件数も表示されます。ファイルパス、コピー元のアプリ、リンクのタイトル、画像内の文字（Mac 上で認識）も検索対象です。
- <kbd>⇥</kbd> でテキスト、リンク、画像、ファイル、カラー、お気に入りを切り替えて絞り込めます。<kbd>Space</kbd> でサイドプレビューを開き、<kbd>⌘B</kbd>（**Pick Words**、単語を選ぶ）でテキストを単語チップに分割して、必要な部分だけをペーストできます。
- パネルの位置は 5 種類：ポインタの横、メニューバーアイコンの下、画面中央、画面右端に全高のサイドバーとして固定、画面下端にカードのシェルフとして固定。<kbd>⌃⇧V</kbd> で画像だけをグリッド表示します。外観はライト、ダーク、システムに合わせるから選べ、macOS 26 では Liquid Glass に対応します。

**ペースト**

- <kbd>↩</kbd> で直前に使っていたアプリにペースト（ペースト先はフッターに表示）、<kbd>⇧↩</kbd> でもう一方の形式（元の形式 ↔ プレーンテキスト）でペースト、<kbd>⌘↩</kbd> はコピーのみ行います。
- <kbd>⌘1</kbd>〜<kbd>⌘9</kbd> で先頭 9 件のいずれかをペースト。どのカードもほかのアプリへドラッグできます。
- カードにポインタを重ねると、お気に入り、プレビュー、削除、ピン留めができます。<kbd>⌘⌫</kbd> で削除、<kbd>⌘Z</kbd> で元に戻せます。

**スクリーンショット**

- <kbd>⇧⌘2</kbd> で画面を静止させます。ポインタを重ねてウインドウを選ぶ（重なったウインドウは <kbd>⇥</kbd> またはスクロールで切り替え）、ドラッグで範囲を選ぶ、または <kbd>Space</kbd> で 1 つのウインドウだけを影付きできれいにキャプチャできます。
- 長方形、楕円、矢印、ペン、蛍光ペン、モザイク、テキスト、番号付きステップで注釈を付けられ、完了するまでいつでも編集できます。
- 結果はコピーされ、**履歴にも保存されます**。画面にピン留めしたり、PNG で保存したり、デバイス上の OCR で文字を抽出したりもできます。ルーペ表示中に <kbd>C</kbd> を押すと、ポインタ位置の色をコピーします。

**物干しロープ**

- 画像を選んで <kbd>⌘L</kbd> を押すと、画面上端のロープに吊るせます（最大 12 枚）。メニューバーの空いている場所から下へドラッグする、ポインタを画面上端にとどめる、<kbd>⌃⌥T</kbd> を押す、またはメニューから選ぶと、ロープが下りてきます。
- 写真をダブルクリックでコピー、アプリへドラッグ、クリックで拡大して注釈を付けられます。**Done & Hang Back**（完了して吊るし直す）を押すと、元の画像を残したまま結果を新しい項目として保存します。ロープ上の写真は履歴の整理で削除されません。

**アドレスガード**

- コピーした Bitcoin、Ethereum / EVM、TRON、Solana、Litecoin のアドレスや銀行カード番号が、同じアプリが前面にあるまま数秒以内にクリップボード内で置き換えられると、両方の値を 1 文字ずつ比較し、違いを赤で示す警告を表示します。**Restore What I Copied**（コピーした内容に戻す）で元に戻せます。
- 置き換えた側の項目は履歴で赤く表示され、ペースト、コピー、ドラッグはできません。Cubby からアドレスをペーストするときは、事前にクリップボードの内容がまだ一致しているかを確認します。
- クリップボードを消去したり、<kbd>⌘V</kbd> を横取りしたりすることはありません。設定は **Settings › Security**（設定 › セキュリティ）で行います。

**翻訳**（macOS 26）

- <kbd>⌘T</kbd> で選択中の項目をパネル横のカードに翻訳、<kbd>⌥↩</kbd> で翻訳とペーストを一度に実行、<kbd>⌥</kbd> を押し続けるとリスト上で翻訳をプレビューできます。
- スクリーンショット中に <kbd>⇧⌘T</kbd> を押すと、文字をブロックごとにその場で翻訳します。
- デフォルトでは Apple のデバイス上の翻訳を使います。自分で設定した OpenAI 互換モデル（DeepSeek、Qwen、Kimi、Zhipu GLM、OpenAI、OpenRouter、ローカルの Ollama、カスタム URL）も使えます。[翻訳](#翻訳)を参照してください。

**プライバシーと仕上がり**

- データはローカルのみに、ログインキーチェーンの鍵で暗号化して保存し、Time Machine の対象外、分析やテレメトリもありません。パスワードマネージャの内容、無視するように指定したアプリ、API キー・秘密鍵・JWT らしきテキストは記録しません。記録はいつでも一時停止できます。[プライバシー](#プライバシー)を参照してください。
- Swift 6 と SwiftUI / AppKit で開発、サードパーティ依存はゼロ、ユニバーサルバイナリ。メニューバーのみで Dock アイコンはありません。インターフェイスは英語と簡体字中国語に対応。VoiceOver、「視差効果を減らす」、「コントラストを上げる」に対応しています。
- 新しいバージョンが出ると、メニューバーアイコンに小さな青い点が表示されます。

## デザイン

v0.3 のインターフェイスは、実装前にモックアップとしてデザインされました。ここでは中国語 UI で表示しており、実装の過程で変わった細部もあります。リリース版のアプリについては[ユーザーガイド](docs/USER-GUIDE.md)を参照してください。すべてのモックアップは [docs/design/ui-upgrade](docs/design/ui-upgrade) にあります。

<table>
  <tr>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/MainLight.png">
        <img src="docs/design/ui-upgrade/Main.png" width="280" alt="フローティングパネルのモックアップ：検索フィールド、カテゴリバー、メモ、GitHub リンク、Swift コード、カラー、画像の各カードと右クリックメニュー">
      </picture><br>
      <sub>種類別カードのフローティングパネル</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/Search.png" width="280" alt="検索のモックアップ：カテゴリ別件数付きのハイライト表示、最初の単語だけで検索し直すよう提案する結果なしの状態、履歴が空の状態"><br>
      <sub>検索、結果なし、空の状態</sub>
    </td>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/ImageGridLight.png">
        <img src="docs/design/ui-upgrade/ImageGrid.png" width="280" alt="画像のみ表示のモックアップ：スクリーンショットと写真の 2 列グリッドとホバー時のツールバー">
      </picture><br>
      <sub>画像のみ（<kbd>⌃⇧V</kbd>）</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/DockRightLight.png">
        <img src="docs/design/ui-upgrade/DockRight.png" width="420" alt="メモのウインドウの横で、画面右端に全高のサイドバーとして固定されたパネルのモックアップ">
      </picture><br>
      <sub>画面右端に固定</sub>
    </td>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/DockBottomLight.png">
        <img src="docs/design/ui-upgrade/DockBottom.png" width="420" alt="画面下端にカードのシェルフとして固定され、選択した画像カードの上にプレビューを開いたパネルのモックアップ">
      </picture><br>
      <sub>画面下端に固定</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/ClotheslineLight.png">
        <img src="docs/design/ui-upgrade/Clothesline.png" width="420" alt="物干しロープのモックアップ：画面上端のロープに 4 枚の写真が留められ、クリックで編集、ダブルクリックでコピー、アプリへドラッグというヒント付き">
      </picture><br>
      <sub>物干しロープ</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/ClotheslineEdit.png" width="420" alt="物干しロープの写真を拡大し、枠、矢印、番号付きステップ、テキスト、モザイクで注釈を付けているモックアップ。コピーと完了して吊るし直すボタン付き"><br>
      <sub>ロープの写真に注釈を付ける</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/TamperAlert.png" width="420" alt="アドレスガードの警告のモックアップ：コピーした Ethereum アドレスと置き換えたアドレスを 1 文字ずつ比較し、違いを赤で表示"><br>
      <sub>アドレスガードの警告</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/Preview.png" width="420" alt="パネル横のサイドプレビューのモックアップ：リッチテキストのメモを全文表示し、翻訳、プレーンテキストとしてペースト、ペーストのボタン付き"><br>
      <sub>サイドプレビュー（Space）</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/Onboarding.png" width="280" alt="ウェルカムガイドのステップ 3 のモックアップ：フローティングパネル、右サイドバー、下部シェルフから選び、外観も選択"><br>
      <sub>4 ステップのウェルカムガイド</sub>
    </td>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/SettingsLight.png">
        <img src="docs/design/ui-upgrade/Settings.png" width="280" alt="サイドバー付き設定画面のモックアップ：一般タブに外観、ショートカット、5 種類のパネル位置、物干しロープのオプション">
      </picture><br>
      <sub>サイドバー付きの設定</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/MenuBar.png" width="280" alt="メニューバーのメニューのモックアップ：ステータス行、クリップボードを開く、画像のみ、スクリーンショット、物干しロープ、パネル位置サブメニュー"><br>
      <sub>メニューバーのメニュー</sub>
    </td>
  </tr>
</table>

## インストール

### Homebrew（推奨）

```sh
brew install --cask no1coder/tap/cubby
```

アップデートは `brew upgrade --cask cubby` で行えます。

### ダウンロード

1. [最新リリース](https://github.com/no1coder/cubby/releases/latest)から `Cubby-x.y.z.dmg` をダウンロードします。
2. 開いて **Cubby** を **Applications**（アプリケーション）フォルダへドラッグします。
3. アプリケーションフォルダから Cubby を起動します（ディスクイメージやダウンロードフォルダからは起動しないでください）。

リリースは Developer ID で署名され、Apple の公証を受けているため、macOS の確認は初回の 1 回だけです。各リリースには `.zip` と `SHA256SUMS.txt` も含まれます。

### ソースからビルド

```sh
git clone https://github.com/no1coder/cubby.git
cd cubby
make install    # builds a Universal release app, copies it to /Applications and launches it
```

Xcode 26 が必要です。署名オプションについては [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。デフォルトのアドホック署名では、再ビルドのたびに macOS がアクセシビリティと画面収録の許可を忘れてしまいます。

## ユーザーガイド

[ユーザーガイド](docs/USER-GUIDE.md)では、すべての機能を順を追って説明しています（英語）。アプリ内では、メニューバーアイコンのメニューから **User Guide** を選んで開けます（**Settings › About** やパネルのショートカットヘルプの下部からも開けます）。

## 初回起動と許可

初回起動時には 4 ステップのガイド（Welcome、Permissions、Choose a Style、Shortcut）が表示され、2 つの許可を求めたうえで、パネルのレイアウトと外観を選び、ショートカットを設定します。メニューバーアイコンの右クリックメニューにある **Setup Guide…** からいつでも開き直せます。

**macOS 15.4 以降でのクリップボードへのアクセス。** ガイド（または **Settings › Privacy**）で **Grant Access** をクリックし、**ペーストを許可** を選びます。何も起きない場合は、何かをコピーしてからもう一度クリックしてください。このダイアログには「常に許可」の選択肢がないため、システム設定 › プライバシーとセキュリティ › 他のアプリからのペースト（macOS 26 より前は「ペースト」）でも Cubby を **許可** に設定してください。macOS が一度確認すると、ボタンは **Open System Settings** に変わり、その画面を直接開けるようになります。

| 許可 | Cubby が必要とする理由 | 許可する場所 |
| --- | --- | --- |
| **クリップボードへのアクセス**（macOS 15.4 以降） | コピーした内容を読み取るため。許可しないと macOS が何度も確認するか、何も記録されません。 | **Grant Access** をクリックして **ペーストを許可** を選び、システム設定 › プライバシーとセキュリティ › 他のアプリからのペースト → Cubby を **許可** に設定 |
| **アクセシビリティ** | 最前面のアプリに <kbd>⌘V</kbd> を送ってペーストするため。許可しないと、項目を選んでもコピーされるだけです。 | システム設定 › プライバシーとセキュリティ › アクセシビリティ → **Cubby** をオン |
| **画面収録**（スクリーンショット用のみ） | スクリーンショットを撮るときに画面をキャプチャするため。起動時やバックグラウンドでは使いません。初めてスクリーンショットを撮るときに確認されます。 | システム設定 › プライバシーとセキュリティ › 画面とシステムオーディオの録音（macOS 14 では「画面収録」）→ **Cubby** をオン |
| **入力監視**（任意） | アドレスガードが、自分の <kbd>⌘C</kbd> / <kbd>⌘X</kbd> と置き換えを区別するのに役立ちます。検知するのはこの 2 つのショートカットだけで、入力内容は一切読み取りません。 | **Settings › Security** › **Grant Access**、またはシステム設定 › プライバシーとセキュリティ › 入力監視 |

画面収録をオンにすると、macOS から Cubby の終了と再起動を求められることがあります。Cubby の画面収録ウインドウにある **Quit & Reopen Cubby** ボタンで両方まとめて行えます。

メニューバーアイコンをクリックするとパネルが開きます。右クリック（または Control キーを押しながらクリック）すると、ステータス、Only Images、Take Screenshot、Show Clothesline、Panel Position、Appearance、Pause Recording、Clear History、User Guide、Setup Guide、Check for Updates、Settings、Quit のメニューが表示されます。

## キーボードショートカット

| キー | 操作 |
| --- | --- |
| <kbd>⇧⌘V</kbd> | パネルを開く / 閉じる（グローバル、変更可） |
| <kbd>⌃⇧V</kbd> | 画像だけを表示してパネルを開く（グローバル、変更・オフ可） |
| <kbd>⌃⌥T</kbd> | 物干しロープを表示 / 非表示（グローバル、変更・オフ可） |
| <kbd>⇧⌘2</kbd> | スクリーンショットを撮る（グローバル、変更・オフ可） |
| 何か入力 | 検索 |
| <kbd>↑</kbd> <kbd>↓</kbd>（画像グリッドと下部シェルフでは <kbd>←</kbd> <kbd>→</kbd>） | 選択を移動 |
| <kbd>↩</kbd> またはダブルクリック | 現在のアプリにペースト |
| <kbd>⇧↩</kbd> / <kbd>⌘↩</kbd> | もう一方の形式でペースト / コピーのみ |
| <kbd>⌘1</kbd> – <kbd>⌘9</kbd> | 1〜9 番目の項目をペースト |
| <kbd>Space</kbd> / <kbd>⌘Y</kbd> | プレビューの切り替え（<kbd>Space</kbd> は検索フィールドが空のときのみ） |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> | 次 / 前のカテゴリ |
| <kbd>⌘B</kbd> | Pick Words（単語を選ぶ） |
| <kbd>⌘P</kbd> | お気に入りに追加 / 解除 |
| <kbd>⇧⌘P</kbd> | 選択した画像を画面にピン留め |
| <kbd>⌘L</kbd> | 選択した画像を物干しロープに吊るす / 外す |
| <kbd>⌘T</kbd> / <kbd>⌥↩</kbd> / <kbd>⌥</kbd> を押し続ける | 翻訳 / 翻訳してペースト / 翻訳をプレビュー（macOS 26） |
| <kbd>⌘⌫</kbd> / <kbd>⌘Z</kbd> | 削除 / 削除を取り消す |
| <kbd>⌘O</kbd> | リンクまたはファイルを開く |
| <kbd>⌘,</kbd> | 設定 |
| <kbd>esc</kbd> | 1 段階戻る：ヘルプやプレビューを閉じる → 検索をクリア → パネルを閉じる |

<details>
<summary><b>スクリーンショットのショートカット</b></summary>
<br>

| キー | 操作 |
| --- | --- |
| クリック / ドラッグ | ハイライトされたウインドウまたは画面を選択 / 範囲を選択 |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> またはスクロール | ポインタの下で重なっているウインドウを順に切り替え（最後は画面全体） |
| <kbd>Space</kbd> | ウインドウモード：ハイライトされたウインドウだけを、隠れた部分なしに影付きでキャプチャ（<kbd>⌥</kbd>-クリックで影なし） |
| ドラッグ中に <kbd>⇧</kbd> / <kbd>⌥</kbd> / <kbd>Space</kbd> を押し続ける | 正方形で選択 / 中心から広げる / 選択範囲を移動 |
| <kbd>⌘A</kbd> | 画面全体を選択 |
| <kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd> | 選択範囲または選択した注釈を 1 pt 移動（<kbd>⇧</kbd> で 10 pt） |
| <kbd>R</kbd> <kbd>O</kbd> <kbd>A</kbd> <kbd>P</kbd> <kbd>H</kbd> <kbd>M</kbd> <kbd>T</kbd> <kbd>N</kbd> | 長方形、楕円、矢印、ペン、蛍光ペン、モザイク、テキスト、番号（同じキーまたは <kbd>V</kbd> でポインタに戻る） |
| <kbd>⌫</kbd> | 選択した注釈を削除 |
| <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> | 注釈を取り消す / やり直す |
| <kbd>C</kbd> | ルーペ位置の色をコピー（<kbd>⇧</kbd> を押すと RGB） |
| <kbd>↩</kbd>、<kbd>⌘C</kbd> またはダブルクリック | 完了：クリップボードと履歴にコピー |
| <kbd>⌘S</kbd> | PNG で保存 |
| <kbd>⌘P</kbd> | 画面にピン留め |
| <kbd>⌘T</kbd> | 文字を抽出してコピー |
| <kbd>⇧⌘T</kbd> | 選択範囲の文字を翻訳（macOS 26） |
| 右クリック | 選択を解除して選び直す。選択がなければキャンセル |
| <kbd>esc</kbd> | キャンセル（何か描いた後は 2 回押す） |

</details>

パネルのフッターにあるキーボードボタンでアプリ内にショートカット一覧を表示でき、カードを右クリックするとその操作が一覧表示されます。物干しロープ、翻訳カード、ピン留めした画像を含む完全なリファレンスは[ユーザーガイド](docs/USER-GUIDE.md#shortcut-reference)にあります。

## 翻訳

macOS 26 では、パネルで項目を選んで <kbd>⌘T</kbd> を押すと、パネルの横に翻訳カードが開き、見出し、リスト、太字、リンクを保ったまま段落ごとに翻訳が表示されます。スクリーンショットでは <kbd>⇧⌘T</kbd> を押すと、元の文字の位置に翻訳を描画します。<kbd>Space</kbd> を押し続けると原文をのぞき見でき、仕切りをドラッグして見比べることもできます。

| スクリーンショットをその場で翻訳 | クリップボードの項目を翻訳 |
| :---: | :---: |
| <img src="docs/assets/screenshots/screenshot-translate-dark.png" alt="英語のウインドウ 2 つのスクリーンショットで、すべてのラベルと行がその場で中国語訳に置き換えられた様子"> | <img src="docs/assets/screenshots/clipboard-translate-dark.png" alt="パネル横の翻訳カードに、英語のメールとその中国語訳が段落ごとに表示されている様子"> |

翻訳エンジンは **Settings › Translation**（設定 › 翻訳）で選びます。

- **System Translation**（デフォルト）：Apple の内蔵翻訳。Mac 上でオフラインで動作します。言語パックをダウンロードする前に macOS が確認します。
- **Large language model**（大規模言語モデル）：OpenAI 互換の Chat Completions サービスならどれでも使えます。DeepSeek、Qwen（Alibaba Cloud Model Studio）、Kimi（Moonshot AI）、Zhipu GLM（および Z.ai）、OpenAI、OpenRouter、Mac 上の Ollama のプリセットがあり、カスタムのベース URL も指定できます。

API キーは macOS のログインキーチェーンに保存され、環境設定、履歴、ログには一切残りません。モデルを使う場合、送信されるのは翻訳するテキストだけです（画像やスクリーンショットの場合は、その中で認識された文字）。画像そのものはアップロードされず、モザイクの下の文字は送信されません。秘密情報らしきテキストは確認後にのみ送信されます（画像からは送信されません）。リモートのサービスには HTTPS が必須で、プレーンな HTTP は `localhost` でのみ使えます。

## プライバシー

- **ローカルのみ、暗号化して保存。** 履歴・画像・ログは `~/Library/Application Support/Cubby/Vault` に暗号化して保存されます。鍵はログインキーチェーンにあり、読み取りを許可されているのは Cubby の署名だけなので、同じユーザで動くほかのアプリやスクリプトには暗号化されたデータしか見えません。このフォルダは本人だけが読み取れ（0700）、ファイルは 0600、Time Machine の対象外です。管理者権限を得たマルウェアや、Cubby のウインドウを見られるアプリは暗号化では防げないため、FileVault もオンにしておいてください。
- **機密性の高い内容は記録しません。** 非表示または一時的とマークされた項目（パスワードマネージャが付けるもの）、無視するアプリ（**Settings › Privacy**）に登録したアプリ、そしてオフにしない限り API キー・秘密鍵・JWT らしきテキストは記録しません。
- **意図した場所にペースト。** Cubby は <kbd>⌘V</kbd> を送る前に、ペースト先のアプリがまだ最前面にあるか、ペーストしようとしているアドレスがクリップボードの内容とまだ一致しているかを確認します。
- **アドレスガードはローカルで完結。** 入力監視を許可しても、検知するのは <kbd>⌘C</kbd> と <kbd>⌘X</kbd> だけで、入力内容は読み取りません。セキュリティログは Mac 上に残り、値は短縮形でのみ記録されます。
- **スクリーンショットと画像内の文字は Mac の中に。** 画面をキャプチャするのはスクリーンショットを撮るときだけで、キャンセルすれば何も残りません。画像内の文字は Apple の Vision フレームワークで Mac 上で認識され、履歴ファイルにのみ保存されます。
- **ネットに接続するのはアップデートと自分で設定した翻訳サービスのみ。** アップデート確認（1 日 1 回、デフォルトでオン、**Settings › General** でオフにできます）は `api.github.com/repos/no1coder/cubby/releases/latest` から最新のバージョン番号を読み取るだけで、何もアップロードしません。設定した言語モデルが受け取るのは、翻訳するテキストだけです。
- **分析、テレメトリ、クラッシュレポートは一切ありません。**

詳しくは [PRIVACY.md](PRIVACY.md) を参照してください。

## よくある質問

<details>
<summary><b>アクセシビリティをオンにしているのに、ペーストされずコピーされるだけです。</b></summary>

macOS はこの許可をアプリのコード署名に結びつけています。アップデート後や、署名の異なるビルドをインストールした後（たとえばソースからのビルドの後にリリース版を入れた場合）、スイッチはオンに見えても実際には効いていないことがあります。システム設定 › プライバシーとセキュリティ › アクセシビリティを開き、**Cubby** を選んで **−** をクリックして削除し、もう一度追加するか、Cubby を再起動して許可し直してください。または次のコマンドを実行します。

```sh
tccutil reset Accessibility io.github.no1coder.Cubby
```

その後 Cubby を開いて、もう一度許可してください。

</details>

<details>
<summary><b>画面収録をオンにしているのに、スクリーンショットを撮るたびに Cubby が許可を求めてきます。</b></summary>

原因は上と同じです。この許可はコード署名に結びついているため、アップデート後や署名の異なるビルドを入れた後は、古い項目がオンに見えても実際には効いていないことがあります。Cubby はこの状態を検知し、**Settings › Privacy** に直し方を表示します。システム設定 › プライバシーとセキュリティ › 画面とシステムオーディオの録音（macOS 14 では「画面収録」）を開き、**Cubby** を選んで **−** をクリックして削除し、**+** をクリックして Cubby をもう一度追加してから、Cubby を終了して開き直してください。または次のコマンドを実行します。

```sh
tccutil reset ScreenCapture io.github.no1coder.Cubby
```

その後スクリーンショットを撮り、もう一度許可してください。

</details>

<details>
<summary><b>macOS に「Cubby を開けません」「検証できません」と表示されます。</b></summary>

公式リリースは公証済みなので、「インターネットからダウンロードされました」という確認が 1 回表示されるだけのはずです。Cubby をこのリポジトリの Releases ページからダウンロードしたか、Homebrew でインストールしたか、そしてアプリケーションフォルダから起動しているかを確認してください。署名は次のコマンドで確認できます。

```sh
spctl -a -vvv /Applications/Cubby.app    # expect: source=Notarized Developer ID
```

確認に失敗した場合はアプリを削除してダウンロードし直し、それでも解決しなければ [Issue を作成](https://github.com/no1coder/cubby/issues/new/choose)してください。Gatekeeper を無効にする必要はありません。

</details>

<details>
<summary><b>アドレスが置き換えられたと警告されました。どうすればいいですか？</b></summary>

アドレスやカード番号をコピーした直後、同じアプリが前面にあるまま、クリップボードの内容が同じ種類の別の値に変わったということです。警告に表示された 2 つの値を比べてください。自分で変えた覚えがなければ **Restore What I Copied** をクリックし、見覚えのないソフトウェアが Mac に入っていないか確認してください。自分で変えた場合（同じアプリで 2 つ目のアドレスをすぐにコピーした場合など）は **I Changed It Myself**（自分で変更した）をクリックします。**Settings › Security** で入力監視を許可すると、Cubby が自分によるコピーを見分けやすくなります。

</details>

<details>
<summary><b>キーチェーンの鍵を Cubby に使わせるか macOS に聞かれました。</b></summary>

Cubby は履歴を暗号化する鍵をログインキーチェーン（`io.github.no1coder.Cubby.history`）に保存しています。

- この確認に表示されるアプリ名は偽装できます。許可するのは、Cubby をインストールまたはアップデートした直後で、しかも Cubby 自身が尋ねているときだけにしてください。それ以外のとき、またはほかのアプリが尋ねてきたときは、必ず「拒否」を選びます。
- 拒否してもデータは失われません。Cubby は **History is locked** と表示し、新しくコピーした内容をメモリに保持します。**Try Again** をクリックして許可すれば、履歴に統合されます。
- 正式リリースの署名は変わらないため、通常のアップデートでは尋ねられません。署名の異なるビルド（自分でビルドしたものなど）を実行した後に、一度だけ表示されます。

</details>

<details>
<summary><b>データはどこに保存されますか？</b></summary>

- 履歴：`~/Library/Application Support/Cubby/Vault`（`history.cubby`、`security-log.cubby`、画像用の `Blobs` フォルダ。すべて暗号化）
- 環境設定：`~/Library/Preferences/io.github.no1coder.Cubby.plist`
- 保存したスクリーンショット：保存ダイアログで選んだ場所。**Ask where to save each time**（毎回保存先を確認）をオフにしている場合は **Settings › Screenshots** で指定したフォルダ（デフォルトは macOS のスクリーンショットと同じフォルダ）

**Settings › History** から Finder でフォルダを表示できます。保存される内容の詳細は [PRIVACY.md](PRIVACY.md) を参照してください。

</details>

<details>
<summary><b>履歴を書き出したりバックアップしたりできますか？</b></summary>

まだできません。読み込みと書き出しは[ロードマップ](docs/ROADMAP.md)に入っています。クリップボードには機密性の高い内容が含まれることが多いため、データフォルダはあえて Time Machine の対象外にしています。書き出し機能が出るまでは、Cubby を終了して `~/Library/Application Support/Cubby` を手動でコピーできます。そのコピーは暗号化されており、ログインキーチェーンにある鍵がなければ読み取れません。

</details>

<details>
<summary><b>Cubby をアンインストールするには？</b></summary>

Homebrew の場合は、次のコマンドでアプリとすべてのデータが削除されます。

```sh
brew uninstall --zap --cask cubby
```

それ以外の場合は、Cubby を終了してから次を実行します。

```sh
rm -rf /Applications/Cubby.app ~/Library/Application\ Support/Cubby
defaults delete io.github.no1coder.Cubby
tccutil reset All io.github.no1coder.Cubby
```

どちらの場合も、履歴の鍵はログインキーチェーンに残ります。あわせて削除するには `security delete-generic-password -s io.github.no1coder.Cubby.history` を実行します。

</details>

## コントリビュート

バグ報告、翻訳、プルリクエストを歓迎します。[CONTRIBUTING.md](CONTRIBUTING.md) では、ソースからのビルド、テスト、コードスタイル、ローカルでの署名について説明しています。[行動規範](CODE_OF_CONDUCT.md)をお読みください。セキュリティ上の問題は [SECURITY.md](SECURITY.md) の手順に従って非公開で報告してください。

## ロードマップ

v0.3 では、固定レイアウト、画像グリッド、物干しロープ、アドレスガード、Pick Words、そして刷新したパネル、設定、ウェルカムガイドが加わりました。今後の予定：経過日数による自動整理、複数選択と結合ペースト、ペーストキュー、テキスト変換、ペースト前の編集、クイックルック、読み込み / 書き出し。スクリーンショットでは、<kbd>⌥</kbd> を押しながらの UI 要素の選択と、前回の選択範囲の復元。詳しくは [docs/ROADMAP.md](docs/ROADMAP.md)、リリースノートは [CHANGELOG.md](CHANGELOG.md) を参照してください。

## ライセンス

[MIT](LICENSE) © 2026 no1coder
