import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 隐私屏模式：通过 Windows 显示拓扑切换实现「本地黑屏、远程照常」。///
/// 与 Win+P 切换是同一套机制（SetDisplayConfig + SDC_TOPOLOGY_*）：
/// - 开启：仅虚拟显示器输出（物理屏无信号，远程画面不受影响）
/// - 关闭：仅内置屏幕输出（恢复正常）
///
/// 前置条件：已安装 IDD 虚拟显示器驱动（如 IddSampleDriver），
/// 否则开启后本地与远程都会黑屏——这是预期行为，需先装驱动。
///
/// 返回错误信息，成功返回 null。
String? setPrivacyScreen({required bool enable}) {
  if (!Platform.isWindows) {
    return '隐私屏模式仅支持 Windows。';
  }
  // SDC_TOPOLOGY_EXTERNAL=8（仅外接屏，虚拟屏视为外接）
  // SDC_TOPOLOGY_INTERNAL=1（仅内置屏）；SDC_APPLY=128
  final topology = enable ? SDC_TOPOLOGY_EXTERNAL : SDC_TOPOLOGY_INTERNAL;
  final flags = SET_DISPLAY_CONFIG_FLAGS(topology | SDC_APPLY);
  final result = SetDisplayConfig(0, nullptr, 0, nullptr, flags);
  if (result != 0) {
    return '切换显示模式失败（错误码 $result）。'
        '请确认已安装虚拟显示器驱动（设置-系统-屏幕 中能看到 2 号显示器）。';
  }
  return null;
}

/// 检测 IDD 虚拟显示器设备是否已安装
/// （Display 类下硬件 ID 含 IddSampleDriver）。
bool isIddVirtualDisplayInstalled() {
  if (!Platform.isWindows) {
    return false;
  }
  final deviceInfoSet = SetupDiGetClassDevs(
    null,
    null,
    null,
    DIGCF_ALLCLASSES | DIGCF_PRESENT,
  ).value;
  if (deviceInfoSet == -1) {
    // INVALID_HANDLE_VALUE
    return false;
  }
  var found = false;
  try {
    var index = 0;
    while (true) {
      final deviceInfoData = calloc<SP_DEVINFO_DATA>();
      deviceInfoData.ref.cbSize = sizeOf<SP_DEVINFO_DATA>();
      final enumerated = SetupDiEnumDeviceInfo(
        deviceInfoSet,
        index,
        deviceInfoData,
      ).value;
      if (!enumerated) {
        free(deviceInfoData);
        break;
      }
      // 先查询硬件 ID 缓冲区大小。
      final requiredSize = calloc<Uint32>();
      SetupDiGetDeviceRegistryProperty(
        deviceInfoSet,
        deviceInfoData,
        SPDRP_HARDWAREID,
        null,
        null,
        0,
        requiredSize,
      );
      final size = requiredSize.value;
      free(requiredSize);
      if (size > 0) {
        final buffer = calloc<Uint16>(size ~/ 2 + 1);
        final ok = SetupDiGetDeviceRegistryProperty(
          deviceInfoSet,
          deviceInfoData,
          SPDRP_HARDWAREID,
          null,
          buffer.cast<Uint8>(),
          size,
          null,
        ).value;
        if (ok) {
          final hardwareId = buffer.cast<Utf16>().toDartString();
          if (hardwareId.toUpperCase().contains('IDDSAMPLEDRIVER')) {
            found = true;
          }
        }
        free(buffer);
      }
      free(deviceInfoData);
      if (found) {
        break;
      }
      index += 1;
    }
  } finally {
    SetupDiDestroyDeviceInfoList(deviceInfoSet);
  }
  return found;
}

/// 查找 IDD 虚拟显示器的设备名（如 `\\.\DISPLAY2`），找不到返回 null。
String? findVirtualDisplayDeviceName() {
  var index = 0;
  while (true) {
    final dd = calloc<DISPLAY_DEVICE>();
    dd.ref.cb = sizeOf<DISPLAY_DEVICE>();
    if (!EnumDisplayDevices(null, index, dd, 0)) {
      free(dd);
      break;
    }
    final deviceString = dd.ref.DeviceString;
    final deviceName = dd.ref.DeviceName;
    final deviceId = dd.ref.DeviceID;
    free(dd);
    // 驱动 INF 的 DeviceName 为 "IddSampleDriver Device"，
    // 硬件 ID 为 ROOT\iddsampledriver（区别于 MuMu 的 Root\MuMuIddDriver）。
    // 不要求当前已连接：对未激活的显示器设置模式同样有效，
    // 切换拓扑后即按该模式输出。
    if (deviceString.toUpperCase().contains('IDDSAMPLEDRIVER') ||
        deviceId.toUpperCase().contains('IDDSAMPLEDRIVER')) {
      return deviceName;
    }
    index += 1;
  }
  return null;
}

/// 读取主显示器（物理屏）的当前分辨率。
/// 返回 [width, height, frequency]，失败返回 null。
(List<int>, int)? readPrimaryDisplayMode() {
  String? primaryName;
  var index = 0;
  while (true) {
    final dd = calloc<DISPLAY_DEVICE>();
    dd.ref.cb = sizeOf<DISPLAY_DEVICE>();
    if (!EnumDisplayDevices(null, index, dd, 0)) {
      free(dd);
      break;
    }
    final name = dd.ref.DeviceName;
    final flags = dd.ref.StateFlags.toInt();
    free(dd);
    if ((flags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0) {
      primaryName = name;
      break;
    }
    index += 1;
  }
  if (primaryName == null) {
    return null;
  }
  final devmode = calloc<DEVMODE>();
  devmode.ref.dmSize = sizeOf<DEVMODE>();
  final namePtr = primaryName.toNativeUtf16();
  final ok = EnumDisplaySettings(
    PCWSTR(namePtr),
    ENUM_CURRENT_SETTINGS,
    devmode,
  );
  free(namePtr);
  if (!ok) {
    free(devmode);
    return null;
  }
  final result = (
    [devmode.ref.dmPelsWidth, devmode.ref.dmPelsHeight],
    devmode.ref.dmDisplayFrequency,
  );
  free(devmode);
  return result;
}

/// 将虚拟显示器设为指定分辨率（运行时生效，无需重启设备）。
/// 返回错误信息，成功返回 null。
String? setVirtualDisplayResolution(
  int width,
  int height, {
  int frequency = 60,
}) {
  final deviceName = findVirtualDisplayDeviceName();
  if (deviceName == null) {
    return '未找到已连接的虚拟显示器，请先安装并启用 IddSampleDriver 驱动。';
  }
  final devmode = calloc<DEVMODE>();
  devmode.ref.dmSize = sizeOf<DEVMODE>();
  devmode.ref.dmFields = DEVMODE_FIELD_FLAGS(
    (DM_BITSPERPEL | DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY)
        .toInt(),
  );
  devmode.ref.dmBitsPerPel = 32;
  devmode.ref.dmPelsWidth = width;
  devmode.ref.dmPelsHeight = height;
  devmode.ref.dmDisplayFrequency = frequency;
  final namePtr = deviceName.toNativeUtf16();
  final result = ChangeDisplaySettingsEx(
    PCWSTR(namePtr),
    devmode,
    CDS_TYPE(0),
    nullptr,
  );
  free(namePtr);
  free(devmode);
  if (result != DISP_CHANGE_SUCCESSFUL) {
    return '设置虚拟屏分辨率失败（错误码 $result）。';
  }
  return null;
}

/// 将虚拟显示器分辨率匹配为物理屏当前分辨率。
/// 返回提示信息（null 表示成功）。
String? matchVirtualDisplayToPrimary() {
  final primary = readPrimaryDisplayMode();
  if (primary == null) {
    return '读取本机分辨率失败。';
  }
  final (size, frequency) = primary;
  return setVirtualDisplayResolution(size[0], size[1], frequency: frequency);
}

/// 进入隐私屏：先切换拓扑让虚拟屏连接，再设置分辨率。
String? enterPrivacyScreen() {
  // 1. 先切换拓扑（仅虚拟显示器），此时虚拟屏才处于连接状态。
  final switchMessage = setPrivacyScreen(enable: true);
  if (switchMessage != null) {
    return switchMessage;
  }
  // 2. 等待虚拟屏完成连接。
  sleep(const Duration(milliseconds: 900));
  // 3. 连接后再把分辨率匹配为物理屏分辨率
  //    （ChangeDisplaySettingsEx 对未连接的显示器会失败）。
  final matchMessage = matchVirtualDisplayToPrimary();
  if (matchMessage != null) {
    return '已进入隐私屏，但分辨率匹配失败：$matchMessage';
  }
  return null;
}
