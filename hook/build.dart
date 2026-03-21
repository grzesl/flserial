import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'dart:io';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final List<String> customFlags = [];
    final List<String> includeDirs = [];
    final List<String> srcFiles = [];

    // Próba dostępu do OS przez config.target.os (nowsze API)
    // lub config.targetOs (starsze API).
    // Sprawdź podpowiedzi w IDE, ale najpewniej zadziała to:

    if (Platform.isWindows) {
      // --- FLAGI DLA WINDOWS (MSVC) ---
      customFlags.addAll([
        '/std:c++17', // Standard C++
        '/O2', // Optymalizacja prędkości
        '/EHsc', // Obsługa wyjątków (kluczowa dla std::thread)
        '/DWIN64', // Definicja platformy
      ]);
      includeDirs.addAll(['src', 'src/windows']);
      srcFiles.addAll(['src/flserial.cpp', 'src/windows/dart_api_dl.c']);
    } else {
      // --- FLAGI DLA MACOS / LINUX (CLANG/GCC) ---
      customFlags.addAll(['-std=c++17', '-O3', '-fvisibility=default']);

      if (Platform.isLinux) {
        includeDirs.addAll(['src', 'src/linux']);
        srcFiles.addAll(['src/flserial.cpp', 'src/linux/dart_api_dl.cpp']);
        customFlags.add('-lstdc++'); // Fix dla braku -lc++ na Linuxie
      } else if (Platform.isMacOS) {
        includeDirs.addAll(['src', 'src/macos']);
        srcFiles.addAll(['src/flserial.cpp', 'src/macos/dart_api_dl.cpp']);
        customFlags.add('-lc++');
      }
    }

    final cbuilder = CBuilder.library(
      name: 'flserial',
      assetName: 'flserial',
      sources: srcFiles,
      includes: includeDirs,
      flags: customFlags,
    );

    await cbuilder.run(output: output, input: config);
  });
}
