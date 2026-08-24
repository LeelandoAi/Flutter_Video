#include "include/lee_video/lee_video_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "lee_video_plugin.h"

void LeeVideoPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  lee_video::LeeVideoPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
