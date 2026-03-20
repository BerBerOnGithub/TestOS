; ===========================================================================
; apps/hello.asm - Hello World using the NatureOS SDK
; ===========================================================================
[BITS 16]
[ORG 0x0000]

%include "sdk.asm"

    mov  ax, cs
    mov  ds, ax

    newline
    print_str msg, CLR_GREEN
    newline

    retf

msg: db ' Hello from a NatureOS app!', 13, 10, 0
