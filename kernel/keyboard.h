#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stdint.h>

void keyboard_init(void);

/* Read one character from the keyboard (blocking) */
char keyboard_getchar(void);

/* Read a line into buf (max len-1 chars + NUL), echoes input */
void keyboard_readline(char *buf, int len);

#endif
