#include <stdint.h>
#include <stdbool.h>
void swimble_audio_release(uint64_t handle);
void swimble_audio_active(uint64_t handle, bool active);
void swimble_audio_capture(uint64_t handle, const float *samples, uint32_t count, uint32_t rate, float gain, int32_t target);
void swimble_audio_playback(uint64_t handle, float *left, float *right, uint32_t frames, float gain);
