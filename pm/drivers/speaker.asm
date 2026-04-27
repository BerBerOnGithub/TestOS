; ===========================================================================
; pm/speaker.asm - PC Speaker (PIT Channel 2) Driver
;
; Provides globally callable functions for audio output in Protected Mode.
; ===========================================================================

[BITS 32]

GLOBAL speaker_play
GLOBAL speaker_stop
GLOBAL speaker_beep

; -
; speaker_play - Starts playing a frequency
; In: EAX = frequency in Hz
; -
speaker_play:
    pusha
    
    ; Prevent division by zero or too low/high freqs
    cmp eax, 18                 ; Min PIT Hz
    jl .done
    cmp eax, 20000              ; Max audible Hz roughly
    jg .done

    ; Calculate divisor: 1193180 / frequency
    mov ebx, eax
    mov eax, 1193180            ; PIT base frequency
    xor edx, edx
    div ebx
    mov ebx, eax                ; EBX = divisor

    ; Set PIT Channel 2 to square wave generator mode
    mov al, 0xB6
    out 0x43, al

    ; Send divisor LSB then MSB to port 0x42
    mov al, bl
    out 0x42, al
    mov al, bh
    out 0x42, al

    ; Enable the speaker by setting bits 0 and 1 of PS/2 port 0x61
    in al, 0x61
    or al, 0x03
    out 0x61, al

.done:
    popa
    ret

; -
; speaker_stop - Stops playing audio
; -
speaker_stop:
    push eax
    in al, 0x61
    and al, 0xFC                ; Clear bits 0 and 1
    out 0x61, al
    pop eax
    ret

; -
; speaker_beep - Plays a frequency for a specific duration (blocking)
; In: EAX = frequency (Hz)
;     EBX = duration in centiseconds (10ms ticks)
; -
speaker_beep:
    pusha
    call speaker_play
    
    ; Get current PIT ticks (100Hz = 10ms per tick)
    mov ecx, [pit_ticks]
    add ecx, ebx                ; Target tick count
    
.wait:
    sti
    hlt
    cmp [pit_ticks], ecx
    jl .wait
    
    call speaker_stop
    popa
    ret
