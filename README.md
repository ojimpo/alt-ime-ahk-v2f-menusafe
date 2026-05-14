# alt-ime-ahk-v2f-menusafe

[ryobeam/alt-ime-ahk-v2f](https://github.com/ryobeam/alt-ime-ahk-v2f) のフォーク。Alt 空打ちで IME を切り替える際、Outlook のリボン / VS Code のメニューバー / CATIA V5 のアクセスキーといった「Alt 単独タップでメニューに奪われる」挙動を回避する。

## 概要

左右 Alt キーの空打ちで IME を OFF/ON する AutoHotKey スクリプト。

* 左 Alt キーの空打ちで IME を「英数」に切り替え
* 右 Alt キーの空打ちで IME を「かな」に切り替え
* Alt キーを押している間に他のキーを打つと通常の Alt キーとして動作

## 動作環境

* Windows 10 / 11
* AutoHotkey v2

## 上流(ryobeam/alt-ime-ahk-v2f)からの差分

上流は Alt 押下直後に `vkFF` をダミー送出して上部メニュー起動を抑制していたが、`vkFF` を未認識のキーとして無視するアプリ（Outlook 等）でリボンが立ち上がってしまう問題があった。本フォークでは以下のように挙動を変更している。

### 1. Office 系（Alt up タイミング）

`LAlt up::` / `RAlt up::` 側でダミー(`F24`)を送る方式に変更。AHK が Alt up を握りつぶしている間に `F24` を注入することで、OS には「Alt + F24 のキーコンボ」に見え、Outlook の「Alt 単独タップでリボン起動」条件が成立しなくなる。`F24` は実在の VK だがどのアプリでも既定の割り当てがなく副作用がない。

`vk07` ではなく `F24` を使う理由: `vk07` / `vkFF` は Office 系がキーとして認識せず素通りするため。

### 2. CATIA V5 等のレガシー Win32 系（Alt down タイミング）

CATIA V5 (`CNEXT.exe`) のプロパティダイアログは Alt 押下時点でアクセスキー入力モードに入る挙動があり、Alt up タイミングの抑止では間に合わない。`*~LAlt::` / `*~RAlt::` で `WinActive("ahk_exe CNEXT.exe")` 条件分岐し、CATIA アクティブ時のみ Alt down 直後にも `F24` を先制注入する。

### 3. VS Code

VS Code (Electron) は Alt 押下時点でメニューバーがフォーカスを奪う。AHK 側ではタイミング的に間に合わないため、VS Code 側の `settings.json` で対処することを推奨する。

```json
{
    "window.customMenuBarAltFocus": false,
    "window.enableMenuBarMnemonics": false
}
```

## 使用方法

```sh
git clone https://github.com/ojimpo/alt-ime-ahk-v2f-menusafe.git
```

任意の場所に展開し、AutoHotkey v2 がインストールされた状態で `alt-ime-ahk-v2f.ahk` をダブルクリックするとタスクトレイに常駐する。

スタートアップ起動は Windows のスタートアップフォルダ(`shell:startup`)に `AutoHotkey64.exe` を target、`.ahk` のパスを argument にしたショートカットを置く。

終了する場合はタスクトレイのアイコンを右クリックし、「Exit」をクリック。

## 参考

* [Altの空打ちで日本語入力(IME)を切り替えるツールを作った](http://www.karakaram.com/alt-ime-on-off/)
* [Autohotkey v2.0のIME制御用 関数群 IMEv2.ahk](https://qiita.com/kenichiro_ayaki/items/d55005df2787da725c6f)
