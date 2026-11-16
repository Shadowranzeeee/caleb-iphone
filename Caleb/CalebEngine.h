#ifndef CALEB_ENGINE_H
#define CALEB_ENGINE_H

#include <stddef.h>

typedef struct caleb_engine caleb_engine;

caleb_engine *caleb_open(const char *path);
void caleb_close(caleb_engine *engine);

// Begin: 0 on success, 1 if the prompt is too long, -1 on failure.
int caleb_begin(caleb_engine *engine, const char *prompt, int output_tokens);
// Prefill: 1 when ready to generate, 0 when more prompt batches remain, -1 on failure.
int caleb_prefill(caleb_engine *engine);
// Next: byte count, 0 at completion, or -1 on failure.
int caleb_next(caleb_engine *engine, char *bytes, size_t capacity);

#endif
