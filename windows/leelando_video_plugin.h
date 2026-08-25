#ifndef FLUTTER_PLUGIN_LEELANDO_VIDEO_PLUGIN_H_
#define FLUTTER_PLUGIN_LEELANDO_VIDEO_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>

#include <memory>

namespace leelando_video {

class LeelandoVideoPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit LeelandoVideoPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~LeelandoVideoPlugin();

  // Disallow copy and assign.
  LeelandoVideoPlugin(const LeelandoVideoPlugin&) = delete;
  LeelandoVideoPlugin& operator=(const LeelandoVideoPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  bool SetFullscreen(bool fullscreen);

  HWND window_ = nullptr;
  bool fullscreen_ = false;
  LONG_PTR previous_style_ = 0;
  LONG_PTR previous_ex_style_ = 0;
  WINDOWPLACEMENT previous_placement_{};
};

}  // namespace leelando_video

#endif  // FLUTTER_PLUGIN_LEELANDO_VIDEO_PLUGIN_H_
