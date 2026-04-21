; ===========================================================================
; NatureOS/include/version.inc - Centralized version strings
; ===========================================================================

%define OS_NAME          "NatureOS"
%define OS_VERSION       "2.0"
%define OS_BUILD         "2.0.0"
%define OS_VER_SHORT     "NatureOS 2.0.0-stable"
%define OS_VER_TEXT      "NatureOS version 2.0"
%define KERNEL_VER       "1.0.0-stable"
%define OS_BUILD_DATE    "2026-02-28"
%define OS_AUTHOR        "Claude (Anthropic)"
%define OS_ARCH_RM       "x86 16-bit"
%define OS_ARCH_PM       "32-bit Protected Mode"

; Filesystem Names
%define FS_NAME          "NatureFS"
%define FS_DATA_NAME     "NatureFS Data Disk"

; Magic numbers
%define FS_MAGIC         "CLFS"
%define FS_MAGIC_VAL     0x53464C43   ; 'CLFS'
%define FS_DATA_MAGIC    "CLFD"
%define FS_DATA_MAGIC_VAL 0x44464C43  ; 'CLFD'
