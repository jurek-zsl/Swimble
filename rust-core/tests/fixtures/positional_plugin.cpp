// Deterministic native plugin used to verify the actual published Mumble ABI.
#include "MumblePlugin.h"
extern "C" {
mumble_error_t mumble_init(mumble_plugin_id_t) { return MUMBLE_STATUS_OK; }
void mumble_shutdown() {}
void mumble_registerAPIFunctions(void *) {}
mumble_version_t mumble_getAPIVersion() { return {1,2,0}; }
MumbleStringWrapper mumble_getName() { return {"Fixture",7,false}; }
uint8_t mumble_initPositionalData(const char *const *, const uint64_t *, size_t) { return MUMBLE_PDEC_OK; }
void mumble_shutdownPositionalData() {}
bool mumble_fetchPositionalData(float *avatar,float *front,float *top,float *camera,float *cameraFront,float *cameraTop,const char **context,const char **identity) {
    avatar[0]=1;avatar[1]=2;avatar[2]=3; camera[0]=4;camera[1]=5;camera[2]=6;
    for (int i=0;i<3;++i) { front[i]=cameraFront[i]=(i==2?1:0); top[i]=cameraTop[i]=(i==1?1:0); }
    *context="world";*identity="player";return true;
}
}
