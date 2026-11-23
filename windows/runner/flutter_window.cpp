#include "flutter_window.h"

#include <commctrl.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// Accessibility-bridge guard (flutter/flutter#175041).
//
// A UI Automation client enumerating the tree while the framework is still
// moving semantics nodes can permanently corrupt the engine-side AXTree and
// crash in AccessibilityBridge::CreateRemoveReparentedNodesUpdate. Background
// tools (remote-desktop hosts, PowerToys, Inspect.exe, OEM utilities)
// enumerate on window open, which enables engine semantics even though no
// assistive technology is in use.
//
// This guard swallows top-level (below) and engine child-view (child subclass
// proc) WM_GETOBJECT requests unless a screen reader is actually active
// (SPI_GETSCREENREADER), so background enumeration never wakes the bridge.
// Real screen-reader users still get full semantics (and the upstream risk
// with it) until the engine fix lands.
//
// Decision record (2026-11-06): startup runs of the Game-first shell logged
// `Failed to update ui::AXTree ... Nodes left pending` every clock tick with
// ZERO top-level WM_GETOBJECT requests reaching this window, so enumeration
// was arriving at the engine's child view window directly and the top-level
// guard alone could not prevent bridge activation. The child subclass below
// closes that hole. The per-run log is retained: it is low-volume and proved
// decisive in diagnosing this.
namespace {
constexpr const wchar_t kAxGuardLogPath[] =
    L"C:\\Users\\Tomi\\AppData\\Local\\Temp\\opencode\\axguard.log";

void AxGuardLogLine(const wchar_t* text, LONG value) {
  FILE* f = nullptr;
  if (_wfopen_s(&f, kAxGuardLogPath, L"a") != 0 || f == nullptr) {
    return;
  }
  fwprintf(f, L"%ls%ld\n", text, value);
  fclose(f);
}

/// Whether an assistive-technology client is active.
bool IsScreenReaderActive() {
  BOOL screen_reader = FALSE;
  return ::SystemParametersInfo(SPI_GETSCREENREADER, 0, &screen_reader, 0) !=
             FALSE &&
         screen_reader != FALSE;
}

constexpr UINT_PTR kAxChildSubclassId = 0xA66E55;

LRESULT CALLBACK AxChildSubclassProc(HWND hwnd, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR /*subclass_id*/,
                                     DWORD_PTR /*ref_data*/) {
  if (message == WM_GETOBJECT) {
    const LONG obj_id = static_cast<LONG>(lparam);
    AxGuardLogLine(L"CHILD-WM_GETOBJECT lparam=", obj_id);
    if (!IsScreenReaderActive()) {
      AxGuardLogLine(L"CHILD-GUARD-BLOCKED lparam=", obj_id);
      return 0;
    }
    AxGuardLogLine(L"CHILD-GUARD-PASSTHROUGH(screenreader) lparam=", obj_id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

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
  // Extend the guard to the engine's child view window (see the header
  // comment): UIA clients that walk the HWND tree query the child directly,
  // bypassing the top-level MessageHandler below. Subclassing chains after
  // the engine's own window proc; only WM_GETOBJECT is intercepted, and a
  // subclass-install failure merely degrades to the top-level-only guard.
  if (SetWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                        AxChildSubclassProc, kAxChildSubclassId,
                        0) == FALSE) {
    AxGuardLogLine(L"CHILD-SUBCLASS-FAILED last-error=",
                   static_cast<LONG>(::GetLastError()));
  }
  AxGuardLogLine(L"ONCREATE-MARKER pid-part=", static_cast<LONG>(::GetCurrentProcessId() & 0x7fffffff));

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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Top-level half of the accessibility-bridge guard (see the header
  // comment; the child view subclass installed in OnCreate covers the rest).
  if (message == WM_GETOBJECT) {
    const LONG obj_id = static_cast<LONG>(lparam);
    AxGuardLogLine(L"WM_GETOBJECT lparam=", obj_id);
    // Block ALL top-level accessibility requests while no screen reader is
    // active — not just OBJID_CLIENT/UiaRoot. A narrower filter still let
    // the bridge activate during the startup bisect, so the trigger is not
    // limited to one object id.
    if (!IsScreenReaderActive()) {
      AxGuardLogLine(L"GUARD-BLOCKED-ALL lparam=", obj_id);
      return 0;
    }
    AxGuardLogLine(L"GUARD-PASSTHROUGH(screenreader) lparam=", obj_id);
  }
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
