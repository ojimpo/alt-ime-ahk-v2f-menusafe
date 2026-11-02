# alt-ime-ahk-v2f-menusafe

左右 Alt の単押しで IME OFF / ON、組み合わせでは通常の Alt として動作する AutoHotkey v2 スクリプト。

Alt 押下を保留し、単押しなら Alt をアプリへ一切送らない。F24 / ダミーキーによるメニュー抑制を廃止した。
Karabiner-Elements の [`to.lazy`](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to/lazy/) と [`to_if_alone`](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to-if-alone/) を参考にしている。Karabiner の全仕様やドライバーを移植したものではない。

Outlook・Word・Excel・メモ帳・VS Code・CATIA V5 など、Alt 単押しでメニューバーやリボンが起動して IME 切替が効かなくなるアプリで使うことを想定している。

> 2026-11-02 に旧方式（Alt を通して F24 を追加する方式）からこの方式へ置き換えた。旧方式が必要なら `49152df` より前のコミットを参照する。

## 使い方

Git もコンパイルも不要。[AutoHotkey v2](https://www.autohotkey.com/download/) が入っていればよい（v1 では動かない）。
ZIP で取得する場合は、リポジトリの Code → Download ZIP を展開して使う。

1. 現在起動中の旧 alt-ime / 他の Alt リマップスクリプトを、タスクトレイから終了する。同時起動しない。
2. このフォルダーの `alt-ime-ahk-v2f-menusafe.ahk` を AutoHotkey v2 で起動する。`DeferredAltCore.ahk` も同じフォルダーに置く。
3. 下記の操作を確認する。まず手動起動で試し、問題なければ下の「スタートアップに登録する」へ進む。

| 操作 | 動作 |
| --- | --- |
| 左 Alt を単押しして離す | IME OFF。Alt は送らない |
| 右 Alt を単押しして離す | IME ON。Alt は送らない |
| Alt を押したまま別のキーを押す | Alt 押下を相手キーの直前に送り、Alt を離すまで保持 |
| Alt を押したままクリック / スクロール | Alt とマウスの組み合わせとして送出。IME は変更しない |
| ポインターの移動だけ | 単押し判定を維持 |
| Ctrl / Shift / Win を先に押してから Alt | 元の物理 Alt を通す。IME は変更しない |
| リモートデスクトップ mstsc.exe 上で Alt を押す | 元の Alt を通す。IME は変更しない |
| Alt だけを1秒より長く押して離す | 何もしない。メニューも起動しない |

単押しの上限はスクリプト先頭の `AloneTimeoutMs := 1000` で変更できる。`0` で時間制限なし。時間が経過しても、それだけで Alt を送ることはない。

終了するときはトレイの **終了（元のAlt動作に戻す）** を選ぶ。旧版に戻すには、このスクリプトを終了してから旧版を起動する。このスクリプト自体はシステム設定、レジストリ、スタートアップを書き換えない。

## スタートアップに登録する

移動しない場所にフォルダーを置き、`Win+R` → `shell:startup` でスタートアップフォルダーを開いてショートカットを作る。旧 alt-ime のショートカットは外す（同時起動しない）。

- リンク先: `AutoHotkey64.exe`（例: `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`）
- 引数: `alt-ime-ahk-v2f-menusafe.ahk` のフルパス（引用符で囲む）
- 作業フォルダー: そのスクリプトのフォルダー

ZIP を展開した場合、ファイルに Mark of the Web が付き、Smart App Control 等に起動を止められることがある。その場合は `Get-ChildItem <フォルダー> -Recurse | Unblock-File` で外す。

## 確認状況

- 自動テスト: 下記のとおり。
- 実機: VS Code、Outlook のメール作成画面、Acrobat Reader の注釈欄で、Alt 単押しによるメニュー起動や入力の妨げが出ずに IME が切り替わることを確認済み。
- Acrobat Reader の注釈欄で変換窓が左上に小さく出る症状は、GUI から IME を切り替えても同じ窓が出るため、このスクリプトとは無関係。
- 未確認: CATIA V5 の数値入力中の Alt 空打ち。不具合があれば Issue に、アプリとバージョン・入力欄・左右どちらの Alt か・押した順番を添えて報告してほしい。

## 確認してほしい操作

- メモ帳 / Outlook / VS Code / CATIA などで、左右 Alt の単押しでメニューにフォーカスが移らず、IME が切り替わる。
- Alt+Tab を一度押す、Alt を押したまま Tab を複数回押す、Alt+Shift+Tab、最後に Alt を離して確定する。
- Alt+F4 は保存不要のテスト用ウィンドウで確認する。Alt+Space、Alt+文字、Alt+クリックも普段のアプリで確認する。
- Alt を離す前に次の文字を押した場合は Alt ショートカットになる。単押しによる IME 切替は Alt を離した時点で確定する。
- ウィンドウ切替後に Tab や文字を単独で押し、Alt が押しっぱなしになっていない。

## 制約

- 通常権限のプロセスから管理者権限のアプリへ入力を注入することは Windows の UIPI により制限される。管理者アプリでも使う場合は、インストール済みの UIAccess 版 AHK または同等の権限で実行して確認する。
- 入力送出に失敗した場合はフックを解除して停止し、トレイ通知を出す。再開にはスクリプトを起動し直す。
- Ctrl+Alt+Del のようなセキュアな操作は通常の入力注入では再現できない。Ctrl を先に押す組み合わせは物理 Alt をそのまま通す。セキュアデスクトップ自体は対象外。
- ゲーム、Raw Input、他のキーフックとの併用、mstsc 以外のリモート接続クライアントは未検証。
- IME 操作は従来の `IMEv2.ahk` と同じ `WM_IME_CONTROL / IMC_SETOPENSTATUS` 方式。64-bit HWND を正しく扱い、応答待ちは50msに制限した。各アプリと IME の対応は実際に使って確認が必要。

## 実装とテスト

`DeferredAltCore.ahk` が単押し / 組み合わせの状態を管理し、メインスクリプトが `WH_KEYBOARD_LL` / `WH_MOUSE_LL` で入出力を処理する。最初の相手キーまたはマウス操作をいったん止め、Alt 押下と同じ `SendInput` バッチで再送して順序を保証する。後続のキーはそのまま通し、Alt 解放だけを対応して送る。IME 操作やファイル書き込みのためにフック内で長時間待機しない。

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut .\tests\run.ahk
```

通常テストは132項目。左右単押し、タイムアウト、Alt+Tab相当の複数回入力、解放順序、修飾キー、拡張キー、マウス併用の状態、終了処理などを確認する。Windows フックの結合テストは、テスト専用タグ付き入力と F23 を使い、Alt が消費されることと再送順序を確認する。IME 操作はテスト内で記録に置き換える。

`tests/run.ahk --desktop` を指定すると、一時的なテスト用ウィンドウ3つを開き、左右 Alt+Tab の連続切替、Alt+Shift+Tab の逆方向切替、Alt 解放も含めた138項目を確認する。完了時にテストウィンドウを閉じ、元のウィンドウを前面に戻す。ほかの Alt リマップを終了してから実行する。

検証結果: AutoHotkey v2 の64bit版 / 32bit版で通常テスト132項目、64bit版でデスクトップテスト138項目が成功。実際の物理キーボードの打鍵タイミングや各アプリの IME 動作は、使って確認が必要。

## 元プロジェクト

- [ryobeam/alt-ime-ahk-v2f](https://github.com/ryobeam/alt-ime-ahk-v2f)
- [karakaram/alt-ime-ahk](https://github.com/karakaram/alt-ime-ahk)

`IMEv2.ahk` は来歴を保つため残している。この版のメインスクリプトからは読み込まない。
