library;

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screen_color_picker_service.dart';

const _vkLButton = 0x01;
const _vkEscape = 0x1B;
const _mousePressedMask = 0x8000;
const _clrInvalid = 0xFFFFFFFF;
const _idcCross = 32515;
const _ocrNormal = 32512;
const _spiSetCursors = 0x0057;

final ffi.DynamicLibrary _user32 = ffi.DynamicLibrary.open('user32.dll');
final ffi.DynamicLibrary _gdi32 = ffi.DynamicLibrary.open('gdi32.dll');

typedef _GetCursorPosNative = ffi.Int32 Function(ffi.Pointer<_Point> lpPoint);
typedef _GetCursorPosDart = int Function(ffi.Pointer<_Point> lpPoint);

final _GetCursorPosDart _getCursorPos = _user32
    .lookupFunction<_GetCursorPosNative, _GetCursorPosDart>('GetCursorPos');

typedef _GetAsyncKeyStateNative = ffi.Int16 Function(ffi.Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

final _GetAsyncKeyStateDart _getAsyncKeyState = _user32
    .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>(
      'GetAsyncKeyState',
    );

typedef _GetDCNative = ffi.IntPtr Function(ffi.IntPtr hWnd);
typedef _GetDCDart = int Function(int hWnd);

final _GetDCDart _getDc = _user32.lookupFunction<_GetDCNative, _GetDCDart>('GetDC');

typedef _ReleaseDCNative = ffi.Int32 Function(ffi.IntPtr hWnd, ffi.IntPtr hDc);
typedef _ReleaseDCDart = int Function(int hWnd, int hDc);

final _ReleaseDCDart _releaseDc = _user32.lookupFunction<_ReleaseDCNative, _ReleaseDCDart>(
  'ReleaseDC',
);

typedef _GetPixelNative = ffi.Uint32 Function(ffi.IntPtr hDc, ffi.Int32 x, ffi.Int32 y);
typedef _GetPixelDart = int Function(int hDc, int x, int y);

final _GetPixelDart _getPixel = _gdi32.lookupFunction<_GetPixelNative, _GetPixelDart>('GetPixel');

typedef _LoadCursorWNative = ffi.IntPtr Function(ffi.IntPtr hInstance, ffi.Pointer<ffi.Uint16> lpCursorName);
typedef _LoadCursorWDart = int Function(int hInstance, ffi.Pointer<ffi.Uint16> lpCursorName);

final _LoadCursorWDart _loadCursor = _user32.lookupFunction<_LoadCursorWNative, _LoadCursorWDart>(
  'LoadCursorW',
);

typedef _SetSystemCursorNative = ffi.Int32 Function(ffi.IntPtr hcur, ffi.Uint32 id);
typedef _SetSystemCursorDart = int Function(int hcur, int id);

final _SetSystemCursorDart _setSystemCursor = _user32
    .lookupFunction<_SetSystemCursorNative, _SetSystemCursorDart>('SetSystemCursor');

typedef _SystemParametersInfoWNative = ffi.Int32 Function(
  ffi.Uint32 uiAction,
  ffi.Uint32 uiParam,
  ffi.Pointer<ffi.Void> pvParam,
  ffi.Uint32 fWinIni,
);
typedef _SystemParametersInfoWDart = int Function(
  int uiAction,
  int uiParam,
  ffi.Pointer<ffi.Void> pvParam,
  int fWinIni,
);

final _SystemParametersInfoWDart _systemParametersInfo = _user32.lookupFunction<
  _SystemParametersInfoWNative,
  _SystemParametersInfoWDart
>('SystemParametersInfoW');

typedef _GetForegroundWindowNative = ffi.IntPtr Function();
typedef _GetForegroundWindowDart = int Function();

final _GetForegroundWindowDart _getForegroundWindow = _user32.lookupFunction<
  _GetForegroundWindowNative,
  _GetForegroundWindowDart
>('GetForegroundWindow');

typedef _SetForegroundWindowNative = ffi.Int32 Function(ffi.IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

final _SetForegroundWindowDart _setForegroundWindow = _user32.lookupFunction<
  _SetForegroundWindowNative,
  _SetForegroundWindowDart
>('SetForegroundWindow');

typedef _SetCaptureNative = ffi.IntPtr Function(ffi.IntPtr hWnd);
typedef _SetCaptureDart = int Function(int hWnd);

final _SetCaptureDart _setCapture = _user32.lookupFunction<_SetCaptureNative, _SetCaptureDart>(
  'SetCapture',
);

typedef _ReleaseCaptureNative = ffi.Int32 Function();
typedef _ReleaseCaptureDart = int Function();

final _ReleaseCaptureDart _releaseCapture = _user32.lookupFunction<
  _ReleaseCaptureNative,
  _ReleaseCaptureDart
>('ReleaseCapture');

base class _Point extends ffi.Struct {
  @ffi.Int32()
  external int x;

  @ffi.Int32()
  external int y;
}

Future<ScreenColorPickResult> pickColor({
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return const ScreenColorPickResult();
  }

  final point = calloc<_Point>();
  final crossCursor = _loadCursor(0, ffi.Pointer<ffi.Uint16>.fromAddress(_idcCross));
  final cursorApplied = crossCursor != 0 && _setSystemCursor(crossCursor, _ocrNormal) != 0;
  final appWindow = _getForegroundWindow();
  final captureActive = appWindow != 0 && _setCapture(appWindow) != 0;

  try {
    var wasPressed = (_getAsyncKeyState(_vkLButton) & _mousePressedMask) != 0;
    var wasEscapePressed = (_getAsyncKeyState(_vkEscape) & _mousePressedMask) != 0;
    final endTime = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(endTime)) {
      final isPressed = (_getAsyncKeyState(_vkLButton) & _mousePressedMask) != 0;
      final isEscapePressed = (_getAsyncKeyState(_vkEscape) & _mousePressedMask) != 0;

      if (!wasEscapePressed && isEscapePressed) {
        return const ScreenColorPickResult(wasCancelled: true);
      }

      if (!wasPressed && isPressed) {
        final success = _getCursorPos(point) != 0;
        if (!success) {
          return const ScreenColorPickResult();
        }

        final hDc = _getDc(0);
        if (hDc == 0) {
          return const ScreenColorPickResult();
        }

        try {
          final pixel = _getPixel(hDc, point.ref.x, point.ref.y);
          if (pixel == _clrInvalid) {
            return const ScreenColorPickResult();
          }

          final red = pixel & 0xFF;
          final green = (pixel >> 8) & 0xFF;
          final blue = (pixel >> 16) & 0xFF;
          return ScreenColorPickResult(
            color: Color.fromARGB(255, red, green, blue),
          );
        } finally {
          _releaseDc(0, hDc);
        }
      }

      wasPressed = isPressed;
      wasEscapePressed = isEscapePressed;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    return const ScreenColorPickResult();
  } finally {
    if (captureActive) {
      _releaseCapture();
    }
    if (appWindow != 0) {
      _setForegroundWindow(appWindow);
    }
    if (cursorApplied) {
      _systemParametersInfo(
        _spiSetCursors,
        0,
        ffi.Pointer<ffi.Void>.fromAddress(0),
        0,
      );
    }
    calloc.free(point);
  }
}
