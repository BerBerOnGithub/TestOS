; ===========================================================================
; NatureOS/include/panic_codes.inc - Kernel Panic Exception String Table
;
; Included by pm/core/panic.asm (inside the panic_screen local scope).
; Each exception entry defines:
;   _name  - short identifier shown on the exception line  (e.g. "#PF  Page Fault")
;   _m1/2/3 - three lines of plain-English explanation
;   _hint  - one targeted recovery hint shown in the "Recovery hints" block
;
; To add a new exception:
;   1. Add the string block below following the existing pattern.
;   2. Add a cmp/jne + mov block in the .lookup_exc chain in panic.asm.
; ===========================================================================

; --- #DE: Divide Error (INT 0x00) ---
.exc_de_name: db "#DE  Divide by Zero", 0
.exc_de_m1:   db "The CPU tried to divide a number by zero.", 0
.exc_de_m2:   db "This is usually a bug in a running program or driver.", 0
.exc_de_m3:   db "The divisor was zero at the time of the instruction.", 0
.exc_de_hint: db "  ->  Check any recently loaded code that performs division.", 0

; --- #DB: Debug Exception (INT 0x01) ---
.exc_db_name: db "#DB  Debug Exception", 0
.exc_db_m1:   db "A debug condition was triggered (breakpoint or single-step).", 0
.exc_db_m2:   db "This should not occur in a production kernel build.", 0
.exc_db_m3:   db "A stray INT 1 or DR watchpoint may be the cause.", 0
.exc_db_hint: db "  ->  Remove debug breakpoints and verify DR register state.", 0

; --- #BP: Breakpoint (INT 0x03) ---
.exc_bp_name: db "#BP  Breakpoint", 0
.exc_bp_m1:   db "An INT 3 breakpoint instruction was executed.", 0
.exc_bp_m2:   db "This is normally used by debuggers and should not appear", 0
.exc_bp_m3:   db "in release builds unless left in accidentally.", 0
.exc_bp_hint: db "  ->  Search the build for stray INT 3 instructions.", 0

; --- #OF: Overflow (INT 0x04) ---
.exc_of_name: db "#OF  Overflow", 0
.exc_of_m1:   db "The INTO instruction was executed and the overflow flag was set.", 0
.exc_of_m2:   db "Signed arithmetic produced a result outside the valid range.", 0
.exc_of_m3:   db "This is rarely triggered by modern code.", 0
.exc_of_hint: db "  ->  Check signed arithmetic near the faulting address.", 0

; --- #BR: BOUND Range Exceeded (INT 0x05) ---
.exc_br_name: db "#BR  Bound Range Exceeded", 0
.exc_br_m1:   db "The BOUND instruction found an index outside its declared range.", 0
.exc_br_m2:   db "An array or buffer index exceeded the limits stored in memory.", 0
.exc_br_m3:   db "This is a bounds-checked array access gone wrong.", 0
.exc_br_hint: db "  ->  Verify array sizes and index values near the fault.", 0

; --- #UD: Invalid Opcode (INT 0x06) ---
.exc_ud_name: db "#UD  Invalid Opcode", 0
.exc_ud_m1:   db "The CPU encountered an instruction it does not understand.", 0
.exc_ud_m2:   db "This may mean the kernel binary is corrupt or was built for", 0
.exc_ud_m3:   db "a different CPU than the one running it.", 0
.exc_ud_hint: db "  ->  Rebuild the kernel and verify your NASM output.", 0

; --- #NM: Device Not Available (INT 0x07) ---
.exc_nm_name: db "#NM  Device Not Available", 0
.exc_nm_m1:   db "The CPU tried to use the FPU or SSE unit, but it is disabled.", 0
.exc_nm_m2:   db "CR0.EM or CR0.TS may be set, blocking floating-point access.", 0
.exc_nm_m3:   db "This can also occur if no FPU is present.", 0
.exc_nm_hint: db "  ->  Check CR0.EM/TS flags and FPU initialisation in the kernel.", 0

; --- #DF: Double Fault (INT 0x08) ---
.exc_df_name: db "#DF  Double Fault", 0
.exc_df_m1:   db "An exception occurred while the CPU was handling another exception.", 0
.exc_df_m2:   db "This usually indicates a corrupted stack or a broken IDT entry.", 0
.exc_df_m3:   db "Recovery is not possible. A reboot is required.", 0
.exc_df_hint: db "  ->  Check the IDT setup and stack allocation in the kernel.", 0

; --- #TS: Invalid TSS (INT 0x0A) ---
.exc_ts_name: db "#TS  Invalid TSS", 0
.exc_ts_m1:   db "The CPU rejected the Task State Segment during a task switch.", 0
.exc_ts_m2:   db "The TSS descriptor is missing, has the wrong type, or is", 0
.exc_ts_m3:   db "pointing to an invalid segment.", 0
.exc_ts_hint: db "  ->  Verify the TSS descriptor in the GDT is correctly set up.", 0

; --- #NP: Segment Not Present (INT 0x0B) ---
.exc_np_name: db "#NP  Segment Not Present", 0
.exc_np_m1:   db "The CPU tried to load a segment descriptor that is marked", 0
.exc_np_m2:   db "as not present. The segment selector in the error code", 0
.exc_np_m3:   db "identifies the offending descriptor.", 0
.exc_np_hint: db "  ->  Check GDT/LDT entries and segment register loads.", 0

; --- #SS: Stack Segment Fault (INT 0x0C) ---
.exc_ss_name: db "#SS  Stack Fault", 0
.exc_ss_m1:   db "The CPU detected a problem with the stack segment.", 0
.exc_ss_m2:   db "This usually means the stack pointer went out of bounds,", 0
.exc_ss_m3:   db "or the stack segment descriptor is invalid.", 0
.exc_ss_hint: db "  ->  Check for stack overflows or misaligned SS in the GDT.", 0

; --- #GP: General Protection Fault (INT 0x0D) ---
.exc_gp_name: db "#GP  General Protection Fault", 0
.exc_gp_m1:   db "The CPU stopped execution due to a privilege or memory violation.", 0
.exc_gp_m2:   db "Common causes: accessing a null segment, a misaligned LGDT/LIDT,", 0
.exc_gp_m3:   db "or executing a privileged instruction from ring 3.", 0
.exc_gp_hint: db "  ->  Check segment selectors, port I/O permissions, and ring level.", 0

; --- #PF: Page Fault (INT 0x0E) ---
.exc_pf_name: db "#PF  Page Fault", 0
.exc_pf_m1:   db "The CPU tried to access a memory address that is not mapped", 0
.exc_pf_m2:   db "or not accessible at the current privilege level. The faulting", 0
.exc_pf_m3:   db "address is shown below in the CR2 register.", 0
.exc_pf_hint: db "  ->  Check the page tables and the pointer that caused the access.", 0

; --- #MF: x87 FPU Floating-Point Error (INT 0x10) ---
.exc_mf_name: db "#MF  FPU Floating-Point Error", 0
.exc_mf_m1:   db "The x87 FPU raised an unmasked floating-point exception.", 0
.exc_mf_m2:   db "Common causes: division by zero, invalid operation, or overflow", 0
.exc_mf_m3:   db "in floating-point arithmetic.", 0
.exc_mf_hint: db "  ->  Check FPU control word masking and floating-point code.", 0

; --- #AC: Alignment Check (INT 0x11) ---
.exc_ac_name: db "#AC  Alignment Check", 0
.exc_ac_m1:   db "A memory access was not aligned to its natural boundary.", 0
.exc_ac_m2:   db "For example, reading a 4-byte value from an odd address.", 0
.exc_ac_m3:   db "Alignment checking is only active when explicitly enabled.", 0
.exc_ac_hint: db "  ->  Ensure data structures are properly aligned in memory.", 0

; --- #MC: Machine Check (INT 0x12) ---
.exc_mc_name: db "#MC  Machine Check", 0
.exc_mc_m1:   db "The CPU detected an unrecoverable hardware error.", 0
.exc_mc_m2:   db "This is typically caused by faulty RAM, a failing CPU, or", 0
.exc_mc_m3:   db "an overheating processor.", 0
.exc_mc_hint: db "  ->  Run a memory test and check CPU temperatures.", 0

; --- #XM / #XF: SIMD Floating-Point Exception (INT 0x13) ---
.exc_xm_name: db "#XM  SIMD Floating-Point Exception", 0
.exc_xm_m1:   db "An SSE or SSE2 floating-point instruction raised an unmasked", 0
.exc_xm_m2:   db "exception. Check the MXCSR register for the specific cause", 0
.exc_xm_m3:   db "(divide by zero, overflow, invalid operation, etc.).", 0
.exc_xm_hint: db "  ->  Check MXCSR masking bits and SSE floating-point code.", 0

; --- Unknown / unhandled exception (fallback) ---
.exc_unk_name: db "Unknown Exception", 0
.exc_unk_m1:   db "The kernel received an unexpected CPU exception.", 0
.exc_unk_m2:   db "This vector is not handled by a dedicated stub.", 0
.exc_unk_m3:   db "Check the IRQ/IDT setup for any unregistered vectors.", 0
.exc_unk_hint: db "  ->  Cross-reference the vector number against the CPU manual.", 0
