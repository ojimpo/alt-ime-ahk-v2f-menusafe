#Requires AutoHotkey v2.0

; Pure event state machine: no hooks, timers or OS input.
class DeferredAltCore {
    __New(aloneTimeout := 1000) {
        this.Timeout := aloneTimeout
        this.Alt := Map()
        this.Held := Map()
    }

    Key(vk, sc, flags, now, bypass := false) {
        r := {block: false, keys: [], ime: -1}
        up := !!(flags & 2)
        if (vk != 0xA4 && vk != 0xA5) {
            if up {
                if this.Held.Has(vk)
                    this.Held.Delete(vk)
                for , a in this.Alt
                    a.alone := false
            } else {
                this.Held[vk] := true
                this.Promote(r.keys)
                if r.keys.Length {
                    r.keys.Push({vk: vk, sc: sc, flags: flags})
                    r.block := true
                }
            }
            return r
        }
        if up {
            if !this.Alt.Has(vk)
                return r ; Alt was held before this script started.
            a := this.Alt[vk]
            this.Alt.Delete(vk)
            r.block := !a.native
            if a.native
                return r
            if a.sent
                r.keys.Push({vk: vk, sc: a.sc, flags: a.ext | 2})
            else if (a.alone && (this.Timeout = 0 || now - a.start <= this.Timeout))
                r.ime := vk = 0xA5 ? 1 : 0
            return r
        }
        if this.Alt.Has(vk) {
            r.block := !this.Alt[vk].native
            return r ; Ignore Alt autorepeat.
        }
        ; Keep pre-held-modifier chords and Remote Desktop native.
        native := bypass || this.ModifierHeld() || this.HasNativeAlt()
        hadAlt := this.Alt.Count > 0
        if hadAlt
            this.Promote(r.keys)
        a := {vk: vk, sc: sc, ext: flags & 1, start: now,
            sent: false, alone: !hadAlt && !native, native: native}
        this.Alt[vk] := a
        if (hadAlt && !native) {
            a.sent := true
            r.keys.Push({vk: vk, sc: sc, flags: flags & 1})
        }
        r.block := !native || r.keys.Length > 0
        if (native && r.keys.Length) {
            a.native := false
            a.sent := true
            r.keys.Push({vk: vk, sc: sc, flags: flags & 1})
        }
        return r
    }

    Promote(keys) {
        for , a in this.Alt {
            a.alone := false
            if (!a.sent && !a.native) {
                a.sent := true
                keys.Push({vk: a.vk, sc: a.sc, flags: a.ext})
            }
        }
    }

    Mouse() {
        keys := []
        this.Promote(keys)
        return keys
    }

    ModifierHeld() {
        for vk in [0x10, 0x11, 0xA0, 0xA1, 0xA2, 0xA3, 0x5B, 0x5C]
            if this.Held.Has(vk)
                return true
        return false
    }

    HasNativeAlt() {
        for , a in this.Alt
            if a.native
                return true
        return false
    }

    ReleaseAll() {
        keys := []
        for , a in this.Alt
            if a.sent
                keys.Push({vk: a.vk, sc: a.sc, flags: a.ext | 2})
        this.Alt.Clear()
        return keys
    }
}
