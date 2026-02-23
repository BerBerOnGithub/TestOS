#ifndef COMMANDS_H
#define COMMANDS_H

/* Each function receives the full argument string (after the command name).
   Returns 0 on success, non-zero on error. */

int cmd_help   (const char *args);
int cmd_echo   (const char *args);
int cmd_clear  (const char *args);
int cmd_calc   (const char *args);
int cmd_mem    (const char *args);
int cmd_time   (const char *args);
int cmd_color  (const char *args);
int cmd_sysinfo(const char *args);
int cmd_reboot (const char *args);
int cmd_ver    (const char *args);
int cmd_beep   (const char *args);

#endif

/* ── New apps ─────────────────────────────────────────── */
int cmd_snake      (const char *args);
int cmd_piano      (const char *args);
int cmd_primes     (const char *args);
int cmd_mandelbrot (const char *args);
int cmd_type       (const char *args);
int cmd_hex        (const char *args);
int cmd_tune       (const char *args);
int cmd_repeat     (const char *args);
