#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  fullscreen_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "flutter_video/fullscreen",
          &flutter::StandardMethodCodec::GetInstance());
  fullscreen_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "enter") {
          SetFullscreen(true);
          result->Success();
          return;
        }
        if (call.method_name() == "exit") {
          SetFullscreen(false);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  fullscreen_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetFullscreen(bool fullscreen) {
  HWND hwnd = GetHandle();
  if (!hwnd || fullscreen_ == fullscreen) {
    return;
  }

  if (fullscreen) {
    previous_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
    previous_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    previous_placement_.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(hwnd, &previous_placement_);

    MONITORINFO monitor_info = {sizeof(MONITORINFO)};
    if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                        &monitor_info)) {
      return;
    }

    SetWindowLongPtr(hwnd, GWL_STYLE,
                     previous_style_ & ~WS_OVERLAPPEDWINDOW);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE,
                     previous_ex_style_ & ~(WS_EX_DLGMODALFRAME |
                                            WS_EX_WINDOWEDGE |
                                            WS_EX_CLIENTEDGE |
                                            WS_EX_STATICEDGE));
    SetWindowPos(hwnd, HWND_TOP, monitor_info.rcMonitor.left,
                 monitor_info.rcMonitor.top,
                 monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
                 monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                 SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    fullscreen_ = true;
    return;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, previous_style_);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, previous_ex_style_);
  SetWindowPlacement(hwnd, &previous_placement_);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  fullscreen_ = false;
}
