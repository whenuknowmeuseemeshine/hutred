#include "flutter_window.h"

#include <cwchar>
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

  // Глобальные медиаклавиши (Fn+F9 и т.п.): ловим их системно, а не только
  // когда окно в фокусе. Если клавишу уже занял другой плеер — просто пропустим.
  media_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "hutred/media_keys",
      &flutter::StandardMethodCodec::GetInstance());
  ::RegisterHotKey(GetHandle(), 1, MOD_NOREPEAT, VK_MEDIA_PLAY_PAUSE);
  ::RegisterHotKey(GetHandle(), 2, MOD_NOREPEAT, VK_MEDIA_NEXT_TRACK);
  ::RegisterHotKey(GetHandle(), 3, MOD_NOREPEAT, VK_MEDIA_PREV_TRACK);
  ::RegisterHotKey(GetHandle(), 4, MOD_NOREPEAT, VK_MEDIA_STOP);
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // Автозапуск с Windows (--minimized): окно не показываем, Hutred в трее.
    if (wcsstr(::GetCommandLineW(), L"--minimized") == nullptr) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  for (int id = 1; id <= 4; ++id) {
    ::UnregisterHotKey(GetHandle(), id);
  }
  media_channel_ = nullptr;
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
    case WM_HOTKEY:
      if (media_channel_) {
        const char* action = nullptr;
        switch (wparam) {
          case 1: action = "playPause"; break;
          case 2: action = "next"; break;
          case 3: action = "previous"; break;
          case 4: action = "stop"; break;
        }
        if (action != nullptr) {
          media_channel_->InvokeMethod(action, nullptr);
          return 0;
        }
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
