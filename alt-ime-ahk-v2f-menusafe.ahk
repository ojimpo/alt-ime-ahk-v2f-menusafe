; 左右 Alt キーの空打ちで IME を ON/OFF する AutoHotkey スクリプト
;
; 左 Alt キーの空打ちで IME OFF
; 右 Alt キーの空打ちで IME ON
; Alt キーを押している間に他のキーを打つと通常の Alt キーとして動作
;
; Author:              ryo
; Original author:     karakaram   http://www.karakaram.com/alt-ime-on-off
;                      SorrowBlue  https://github.com/SorrowBlue/alt-ime-ahk-mod-v2

#Include "IMEv2.ahk"

; Razer Synapseなど、キーカスタマイズ系のツールを併用しているときのエラー対策
A_MaxHotkeysPerInterval := 350

; 既存のインスタンスが存在する場合、終了して新たにインスタンスを開始
#SingleInstance Force

; メニュー項目
Tray:= A_TrayMenu
Tray.Add(A_ScriptName, AppName)
Tray.Disable(A_ScriptName)
Tray.Default := A_ScriptName
Tray.Add()
Tray.Add("Check for Updates...", CheckForUpdates)
Tray.Add("GitHub Repo / Readme", GitHubRepoReadme)
Tray.Add()
Tray.Delete()
Tray.AddStandard()
Return

AppName(A_ThisMenuItem, A_ThisMenuItemPos, MyMenu)
{
    Return
}

CheckForUpdates(A_ThisMenuItem, A_ThisMenuItemPos, MyMenu)
{
    Run("https://github.com/ojimpo/alt-ime-ahk-v2f-menusafe/releases/latest")
    Return
}

GitHubRepoReadme(A_ThisMenuItem, A_ThisMenuItemPos, MyMenu)
{
    Run("https://github.com/ojimpo/alt-ime-ahk-v2f-menusafe")
    Return
}

; 主要なキーを HotKey に設定し、何もせずパススルーする
*~a::
*~b::
*~c::
*~d::
*~e::
*~f::
*~g::
*~h::
*~i::
*~j::
*~k::
*~l::
*~m::
*~n::
*~o::
*~p::
*~q::
*~r::
*~s::
*~t::
*~u::
*~v::
*~w::
*~x::
*~y::
*~z::
*~1::
*~2::
*~3::
*~4::
*~5::
*~6::
*~7::
*~8::
*~9::
*~0::
*~F1::
*~F2::
*~F3::
*~F4::
*~F5::
*~F6::
*~F7::
*~F8::
*~F9::
*~F10::
*~F11::
*~F12::
*~`::
*~~::
*~!::
*~@::
*~#::
*~$::
*~%::
*~^::
*~&::
*~*::
*~(::
*~)::
*~-::
*~_::
*~=::
*~+::
*~[::
*~{::
*~]::
*~}::
*~\::
*~|::
*~;::
*~'::
*~"::
*~,::
*~<::
*~.::
*~>::
*~/::
*~?::
*~Esc::
*~Tab::
*~Space::
*~Left::
*~Right::
*~Up::
*~Down::
*~Enter::
*~PrintScreen::
*~Delete::
*~Home::
*~End::
*~PgUp::
*~PgDn::
{
    Return
}

; メニュー抑止: Alt 押下時に F24 を先制注入してメニュー起動条件を破壊
; F24 はどのアプリでも既定の割り当てが無いので副作用なし
; (上流 ryobeam/alt-ime-ahk-v2f が vkFF でやろうとしていたのと同じ思想で、
;  メモ帳・CATIA V5 など Alt down で反応するレガシー Win32 アプリにも有効)
*~LAlt::
{
    Send("{Blind}{F24}")
    Return
}
*~RAlt::
{
    Send("{Blind}{F24}")
    Return
}

; 左 Alt 空打ちで IME を OFF
; Alt up を AHK が握りつぶしている間に F24 を送ると OS には「Alt+F24 のコンボ」に見え、
; Outlook のリボン起動条件(Alt 単独タップ)が成立しなくなる
#HotIf !WinActive("ahk_exe mstsc.exe")
LAlt up::
{
    if (A_PriorHotkey == "*~LAlt") {
        Send("{Blind}{F24}")
        Send("{LAlt up}")
        IME_SET(0)
    } else {
        Send("{LAlt up}")
    }
    Return
}
#HotIf

; 右 Alt 空打ちで IME を ON
#HotIf !WinActive("ahk_exe mstsc.exe")
RAlt up::
{
    if (A_PriorHotkey == "*~RAlt") {
        Send("{Blind}{F24}")
        Send("{RAlt up}")
        IME_SET(1)
    } else {
        Send("{RAlt up}")
    }
    Return
}
#HotIf

