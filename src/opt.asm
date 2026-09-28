; =============================================================================
; opt.asm - slow paths of the arcade's hot loops rewritten in place
; =============================================================================
; tools/patch_arcade.py (speed_patches) rewrites hot arcade loops at their own
; addresses with faster code that has the same RAM effects; the rare paths
; call in here through this jump table (entry k at OPT_BASE + 3k). `make
; validate` compares the arcade work RAM with MAME's every frame.
; =============================================================================
OPT_BASE        equ $BD00       ; (tools/patch_arcade.py OPT_BASE)

opt_table:
        assert $ == OPT_BASE
        jp opt_snd_slot         ; +0 sound tick $5A90
        jp opt_spr_copy         ; +3 the handler's sprite RAM copy ($00C8)

; Sound tick: HL -> a request-flag byte with bit 0, 1 or 2 set, B = the
; loop count. The original three tests, in their order, with IX = the byte
; (the called routines use IX and B). Preserves HL, B.
opt_snd_slot:
        push hl
        push hl
        pop ix
        bit 2, (ix+0)
        call nz, $5AF6
        bit 0, (ix+0)
        call nz, $5B1D
        bit 1, (ix+0)
        call nz, $5AF6
        pop hl
        ret

; The handler's sprite RAM copy, and a flag for sprites_update: vblanks with
; no new sprite data keep the SAT as it is (an overrunning handler then gets
; the time back).
opt_spr_copy:
        call $026D
        push af
        ld a, 1
        ld (spr_new), a
        pop af
        ret
