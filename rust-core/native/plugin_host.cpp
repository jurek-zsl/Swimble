// C++ is used only to bridge Mumble's legacy std::string/wstring ABI.
// Protocol, positional policy, and lifecycle remain in Rust.
#define EXTERNAL_MUMBLE_PLUGIN_DEFAULT_IMPLEMENTATIONS_
#include "MumblePlugin.h"
#define MUMBLE_ALLOW_DEPRECATED_LEGACY_PLUGIN_API
#include "mumble_legacy_plugin.h"
#include <dlfcn.h>
#include <cwchar>
#include <cstring>
#include <vector>
#include <algorithm>
#ifdef __APPLE__
#include <libproc.h>
#endif

static std::string utf8(const std::wstring &text) {
    std::string out;
    for (uint32_t c : text) {
        if (c <= 0x7f) out.push_back(static_cast<char>(c));
        else if (c <= 0x7ff) { out.push_back(static_cast<char>(0xc0 | c>>6)); out.push_back(static_cast<char>(0x80 | (c&63))); }
        else if (c <= 0xffff) { out.push_back(static_cast<char>(0xe0 | c>>12)); out.push_back(static_cast<char>(0x80 | ((c>>6)&63))); out.push_back(static_cast<char>(0x80 | (c&63))); }
        else if (c <= 0x10ffff) { out.push_back(static_cast<char>(0xf0 | c>>18)); out.push_back(static_cast<char>(0x80 | ((c>>12)&63))); out.push_back(static_cast<char>(0x80 | ((c>>6)&63))); out.push_back(static_cast<char>(0x80 | (c&63))); }
    }
    return out;
}
template<typename> struct Unavailable;
template<typename... Args> struct Unavailable<mumble_error_t(*)(Args...)> {
    static mumble_error_t call(Args...) { return MUMBLE_EC_GENERIC_ERROR; }
};
struct Host {
    void *library = nullptr;
    MumblePlugin *legacy = nullptr; MumblePlugin2 *legacy2 = nullptr;
    decltype(&mumble_initPositionalData) initpos = nullptr;
    decltype(&mumble_fetchPositionalData) fetch = nullptr;
    decltype(&mumble_shutdownPositionalData) stoppos = nullptr;
    decltype(&mumble_shutdown) stop = nullptr;
    bool linked = false; std::string context, identity, name;
    mumble_api_t api{};
    ~Host() { if (linked) { if (legacy) legacy->unlock(); else stoppos(); } if (stop) stop(); if (library) dlclose(library); }
};
extern "C" void *swimble_plugin_open(const char *path) {
    auto host = new Host;
    host->library = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!host->library) { delete host; return nullptr; }
    auto legacy = reinterpret_cast<mumblePluginFunc>(dlsym(host->library, "getMumblePlugin"));
    if (legacy) {
        host->legacy = legacy();
        if (!host->legacy || host->legacy->magic != MUMBLE_PLUGIN_MAGIC || !host->legacy->fetch || !host->legacy->trylock || !host->legacy->unlock) { delete host; return nullptr; }
        auto get2 = reinterpret_cast<mumblePlugin2Func>(dlsym(host->library, "getMumblePlugin2"));
        if (get2) { auto p = get2(); if (p && p->magic == MUMBLE_PLUGIN_MAGIC_2 && p->version == 2) host->legacy2 = p; }
        host->name = utf8(host->legacy->shortname);
        return host;
    }
    auto version = reinterpret_cast<decltype(&mumble_getAPIVersion)>(dlsym(host->library, "mumble_getAPIVersion"));
    if (!version || version().major != 1 || version().minor != 2) { delete host; return nullptr; }
    auto info = reinterpret_cast<decltype(&mumble_setMumbleInfo)>(dlsym(host->library, "mumble_setMumbleInfo"));
    if (info) info({1,5,0},{1,2,0},{1,2,0});
    auto init = reinterpret_cast<decltype(&mumble_init)>(dlsym(host->library, "mumble_init"));
    auto reg = reinterpret_cast<decltype(&mumble_registerAPIFunctions)>(dlsym(host->library, "mumble_registerAPIFunctions"));
    host->initpos = reinterpret_cast<decltype(host->initpos)>(dlsym(host->library, "mumble_initPositionalData"));
    host->fetch = reinterpret_cast<decltype(host->fetch)>(dlsym(host->library, "mumble_fetchPositionalData"));
    host->stoppos = reinterpret_cast<decltype(host->stoppos)>(dlsym(host->library, "mumble_shutdownPositionalData"));
    if (!init || !reg || !host->initpos || !host->fetch || !host->stoppos) { delete host; return nullptr; }
    auto &api = host->api;
    api.freeMemory = Unavailable<decltype(api.freeMemory)>::call;
    api.getActiveServerConnection = Unavailable<decltype(api.getActiveServerConnection)>::call;
    api.isConnectionSynchronized = Unavailable<decltype(api.isConnectionSynchronized)>::call;
    api.getLocalUserID = Unavailable<decltype(api.getLocalUserID)>::call;
    api.getUserName = Unavailable<decltype(api.getUserName)>::call;
    api.getChannelName = Unavailable<decltype(api.getChannelName)>::call;
    api.getAllUsers = Unavailable<decltype(api.getAllUsers)>::call;
    api.getAllChannels = Unavailable<decltype(api.getAllChannels)>::call;
    api.getChannelOfUser = Unavailable<decltype(api.getChannelOfUser)>::call;
    api.getUsersInChannel = Unavailable<decltype(api.getUsersInChannel)>::call;
    api.getLocalUserTransmissionMode = Unavailable<decltype(api.getLocalUserTransmissionMode)>::call;
    api.isUserLocallyMuted = Unavailable<decltype(api.isUserLocallyMuted)>::call;
    api.isLocalUserMuted = Unavailable<decltype(api.isLocalUserMuted)>::call;
    api.isLocalUserDeafened = Unavailable<decltype(api.isLocalUserDeafened)>::call;
    api.getUserHash = Unavailable<decltype(api.getUserHash)>::call;
    api.getServerHash = Unavailable<decltype(api.getServerHash)>::call;
    api.getUserComment = Unavailable<decltype(api.getUserComment)>::call;
    api.getChannelDescription = Unavailable<decltype(api.getChannelDescription)>::call;
    api.requestLocalUserTransmissionMode = Unavailable<decltype(api.requestLocalUserTransmissionMode)>::call;
    api.requestUserMove = Unavailable<decltype(api.requestUserMove)>::call;
    api.requestMicrophoneActivationOvewrite = Unavailable<decltype(api.requestMicrophoneActivationOvewrite)>::call;
    api.requestLocalMute = Unavailable<decltype(api.requestLocalMute)>::call;
    api.requestLocalUserMute = Unavailable<decltype(api.requestLocalUserMute)>::call;
    api.requestLocalUserDeaf = Unavailable<decltype(api.requestLocalUserDeaf)>::call;
    api.requestSetLocalUserComment = Unavailable<decltype(api.requestSetLocalUserComment)>::call;
    api.findUserByName = Unavailable<decltype(api.findUserByName)>::call;
    api.findChannelByName = Unavailable<decltype(api.findChannelByName)>::call;
    api.getMumbleSetting_bool = Unavailable<decltype(api.getMumbleSetting_bool)>::call;
    api.getMumbleSetting_int = Unavailable<decltype(api.getMumbleSetting_int)>::call;
    api.getMumbleSetting_double = Unavailable<decltype(api.getMumbleSetting_double)>::call;
    api.getMumbleSetting_string = Unavailable<decltype(api.getMumbleSetting_string)>::call;
    api.setMumbleSetting_bool = Unavailable<decltype(api.setMumbleSetting_bool)>::call;
    api.setMumbleSetting_int = Unavailable<decltype(api.setMumbleSetting_int)>::call;
    api.setMumbleSetting_double = Unavailable<decltype(api.setMumbleSetting_double)>::call;
    api.setMumbleSetting_string = Unavailable<decltype(api.setMumbleSetting_string)>::call;
    api.sendData = Unavailable<decltype(api.sendData)>::call;
    api.log = Unavailable<decltype(api.log)>::call;
    api.playSample = Unavailable<decltype(api.playSample)>::call;
    // Non-positional host API requests fail explicitly. No null function slots.
    reg(&api);
    if (init(1) != MUMBLE_STATUS_OK) { delete host; return nullptr; }
    host->stop = reinterpret_cast<decltype(host->stop)>(dlsym(host->library, "mumble_shutdown"));
    auto name = reinterpret_cast<decltype(&mumble_getName)>(dlsym(host->library, "mumble_getName"));
    if (name) {
        auto value = name(); if (value.data && value.size < 4096) host->name.assign(value.data, value.size);
        auto release = reinterpret_cast<decltype(&mumble_releaseResource)>(dlsym(host->library, "mumble_releaseResource"));
        if (value.needsReleasing && release) release(value.data);
    }
    return host;
}
extern "C" void swimble_plugin_close(void *pointer) { delete static_cast<Host *>(pointer); }
extern "C" bool swimble_plugin_fetch(void *pointer, float *vectors, char *context, size_t context_cap, char *identity, size_t identity_cap) {
    auto host = static_cast<Host *>(pointer); if (!host) return false;
    if (!host->linked) {
        std::vector<std::string> names; std::vector<uint64_t> pids;
#ifdef __APPLE__
        int count = proc_listallpids(nullptr, 0); std::vector<int> ids(count + 64);
        count = proc_listallpids(ids.data(), static_cast<int>(ids.size()*sizeof(int)));
        for (int i=0; i<count; ++i) { char path[PROC_PIDPATHINFO_MAXSIZE]{}; if (proc_pidpath(ids[i], path, sizeof(path)) > 0) { std::string name(path); auto slash = name.find_last_of('/'); names.push_back(slash == std::string::npos ? name : name.substr(slash+1)); pids.push_back(ids[i]); } }
#endif
        if (host->legacy) {
            if (host->legacy2) { std::multimap<std::wstring, unsigned long long> processes; for (size_t i=0;i<names.size();++i) processes.emplace(std::wstring(names[i].begin(), names[i].end()),pids[i]); host->linked = host->legacy2->trylock(processes) != 0; }
            else host->linked = host->legacy->trylock() != 0;
        } else {
            std::vector<const char *> pointers; for (const auto &name : names) pointers.push_back(name.c_str());
            host->linked = host->initpos(pointers.data(),pids.data(),pids.size()) == MUMBLE_PDEC_OK;
        }
        if (!host->linked) return false;
    }
    bool ok = false;
    if (host->legacy) {
        std::wstring id;
        ok = host->legacy->fetch(vectors,vectors+3,vectors+6,vectors+9,vectors+12,vectors+15,host->context,id) != 0;
        host->identity = utf8(id);
    } else {
        const char *ctx = nullptr, *id = nullptr;
        ok = host->fetch(vectors,vectors+3,vectors+6,vectors+9,vectors+12,vectors+15,&ctx,&id);
        host->context = ctx ? std::string(ctx, strnlen(ctx,8192)) : "";
        host->identity = id ? std::string(id, strnlen(id,8192)) : "";
    }
    if (!ok) { if(host->legacy) host->legacy->unlock(); else host->stoppos(); host->linked = false; return false; }
    auto full_context = host->name + std::string(1,'\0') + host->context;
    // Context is binary: report its length through the return buffer prefix.
    auto length = static_cast<uint32_t>(std::min(full_context.size(),context_cap-4));
    memcpy(context,&length,4); memcpy(context+4,full_context.data(),length);
    std::strncpy(identity,host->identity.c_str(),identity_cap-1); identity[identity_cap-1] = 0;
    return true;
}
