#include "CalebEngine.h"
#include <TargetConditionals.h>
#include <llama/llama.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

enum { context_size = 2048, batch_size = 128 };

struct caleb_engine {
    struct llama_model *model;
    struct llama_context *context;
    struct llama_sampler *sampler;
    const struct llama_vocab *vocab;
    llama_token prompt[context_size];
    int prompt_size;
    int prompt_offset;
    int remaining;
};

caleb_engine *caleb_open(const char *path) {
    caleb_engine *engine = calloc(1, sizeof(*engine));
    if (!engine) return NULL;
    llama_backend_init();

    struct llama_model_params model_params = llama_model_default_params();
#if TARGET_OS_SIMULATOR
    model_params.n_gpu_layers = 0;
#else
    model_params.n_gpu_layers = 99;
#endif
    engine->model = llama_model_load_from_file(path, model_params);
    if (!engine->model) goto failure;

    struct llama_context_params params = llama_context_default_params();
    params.n_ctx = context_size;
    params.n_batch = batch_size;
    params.n_ubatch = batch_size;
    params.n_threads = 2;
    params.n_threads_batch = 4;
    engine->context = llama_init_from_model(engine->model, params);
    if (!engine->context) goto failure;
    engine->vocab = llama_model_get_vocab(engine->model);
    return engine;

failure:
    caleb_close(engine);
    return NULL;
}

void caleb_close(caleb_engine *engine) {
    if (!engine) return;
    if (engine->sampler) llama_sampler_free(engine->sampler);
    if (engine->context) llama_free(engine->context);
    if (engine->model) llama_model_free(engine->model);
    llama_backend_free();
    free(engine);
}

int caleb_begin(caleb_engine *engine, const char *prompt, int output_tokens) {
    size_t length = strlen(prompt);
    if (output_tokens <= 0 || output_tokens >= context_size) return -1;
    if (length > INT_MAX) return 1;
    int count = llama_tokenize(engine->vocab, prompt, (int)length, engine->prompt,
                               context_size - output_tokens, false, true);
    if (count < 0) return 1;
    if (count == 0) return -1;

    if (engine->sampler) llama_sampler_free(engine->sampler);
    engine->sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (!engine->sampler) return -1;
    llama_sampler_chain_add(engine->sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(engine->sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(engine->sampler, llama_sampler_init_temp(0.65f));
    llama_sampler_chain_add(engine->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    llama_memory_clear(llama_get_memory(engine->context), false);
    engine->prompt_size = count;
    engine->prompt_offset = 0;
    engine->remaining = output_tokens;
    return 0;
}

int caleb_prefill(caleb_engine *engine) {
    int count = engine->prompt_size - engine->prompt_offset;
    if (count <= 0) return 1;
    if (count > batch_size) count = batch_size;
    if (llama_decode(engine->context, llama_batch_get_one(engine->prompt + engine->prompt_offset, count))) {
        return -1;
    }
    engine->prompt_offset += count;
    return engine->prompt_offset == engine->prompt_size;
}

int caleb_next(caleb_engine *engine, char *bytes, size_t capacity) {
    while (engine->remaining > 0) {
        --engine->remaining;
        llama_token token = llama_sampler_sample(engine->sampler, engine->context, -1);
        if (llama_vocab_is_eog(engine->vocab, token)) return 0;
        int count = llama_token_to_piece(engine->vocab, token, bytes, (int)capacity, 0, false);
        if (count < 0) return -1;
        if (engine->remaining > 0 && llama_decode(engine->context, llama_batch_get_one(&token, 1))) {
            return -1;
        }
        if (count > 0) return count;
    }
    return 0;
}
