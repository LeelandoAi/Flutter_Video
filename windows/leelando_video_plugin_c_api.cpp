#include "include/leelando_video/leelando_video_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "leelando_video_plugin.h"

void LeelandoVideoPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  leelando_video::LeelandoVideoPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
