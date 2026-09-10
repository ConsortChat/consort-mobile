#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

namespace {

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"Zulip";
constexpr ULONG_PTR kWebAuthMessageId = 0x5A554C49;  // "ZULI"

bool IsWebAuthUrl(const std::string& value) {
  constexpr char kPrefix[] = "zulip://login";
  return value.compare(0, sizeof(kPrefix) - 1, kPrefix) == 0;
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, utf8_string.data(),
      target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

bool ForwardWebAuthUrlToExistingInstance(
    const std::vector<std::string>& command_line_arguments) {
  if (command_line_arguments.size() != 1 ||
      !IsWebAuthUrl(command_line_arguments.front())) {
    return false;
  }

  HWND window = ::FindWindow(kWindowClassName, kWindowTitle);
  if (window == nullptr) {
    return false;
  }

  const std::string& url = command_line_arguments.front();
  COPYDATASTRUCT copy_data = {};
  copy_data.dwData = kWebAuthMessageId;
  copy_data.cbData = static_cast<DWORD>(url.size() + 1);
  copy_data.lpData = const_cast<char*>(url.c_str());

  DWORD_PTR result = 0;
  if (::SendMessageTimeout(
          window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data),
          SMTO_ABORTIFHUNG | SMTO_BLOCK, 5000, &result) == 0) {
    return false;
  }

  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
  return true;
}
