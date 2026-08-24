#include "lee_video_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace lee_video {

// static
void LeeVideoPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "lee_video/fullscreen",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<LeeVideoPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

LeeVideoPlugin::LeeVideoPlugin(flutter::PluginRegistrarWindows* registrar) {
  HWND child_window = registrar->GetView()->GetNativeWindow();
  window_ = GetAncestor(child_window, GA_ROOT);
  if (window_ == nullptr) {
    window_ = child_window;
  }
}

LeeVideoPlugin::~LeeVideoPlugin() {
  if (fullscreen_ && IsWindow(window_)) {
    SetFullscreen(false);
  }
}

void LeeVideoPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  bool requested_fullscreen;
  if (method_call.method_name() == "enter") {
    requested_fullscreen = true;
  } else if (method_call.method_name() == "exit") {
    requested_fullscreen = false;
  } else {
    result->NotImplemented();
    return;
  }

  if (SetFullscreen(requested_fullscreen)) {
    result->Success();
  } else {
    result->Error("fullscreen_failed",
                  "The Windows host window could not change fullscreen state.");
  }
}

bool LeeVideoPlugin::SetFullscreen(bool fullscreen) {
  if (!IsWindow(window_)) {
    return false;
  }
  if (fullscreen_ == fullscreen) {
    return true;
  }

  if (fullscreen) {
    previous_style_ = GetWindowLongPtr(window_, GWL_STYLE);
    previous_ex_style_ = GetWindowLongPtr(window_, GWL_EXSTYLE);
    previous_placement_.length = sizeof(WINDOWPLACEMENT);
    if (!GetWindowPlacement(window_, &previous_placement_)) {
      return false;
    }

    MONITORINFO monitor_info = {sizeof(MONITORINFO)};
    if (!GetMonitorInfo(
            MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
            &monitor_info)) {
      return false;
    }

    SetWindowLongPtr(window_, GWL_STYLE,
                     previous_style_ & ~WS_OVERLAPPEDWINDOW);
    SetWindowLongPtr(window_, GWL_EXSTYLE,
                     previous_ex_style_ & ~(WS_EX_DLGMODALFRAME |
                                            WS_EX_WINDOWEDGE |
                                            WS_EX_CLIENTEDGE |
                                            WS_EX_STATICEDGE));
    if (!SetWindowPos(
            window_, HWND_TOP, monitor_info.rcMonitor.left,
            monitor_info.rcMonitor.top,
            monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
            monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
            SWP_NOOWNERZORDER | SWP_FRAMECHANGED)) {
      SetWindowLongPtr(window_, GWL_STYLE, previous_style_);
      SetWindowLongPtr(window_, GWL_EXSTYLE, previous_ex_style_);
      return false;
    }
    fullscreen_ = true;
    return true;
  }

  SetWindowLongPtr(window_, GWL_STYLE, previous_style_);
  SetWindowLongPtr(window_, GWL_EXSTYLE, previous_ex_style_);
  if (!SetWindowPlacement(window_, &previous_placement_)) {
    return false;
  }
  if (!SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                        SWP_NOOWNERZORDER | SWP_FRAMECHANGED)) {
    return false;
  }
  fullscreen_ = false;
  return true;
}

}  // namespace lee_video
