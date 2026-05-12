import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final List<String> customFlags = [];
    final List<String> includeDirs = [];
    final List<String> srcFiles = [];

    final targetOS = input.config.code.targetOS;

    if (targetOS == OS.windows) {
      customFlags.addAll(['/std:c++17', '/O2', '/EHsc', '/DWIN64']);
      includeDirs.addAll(['src', 'src/windows']);
      srcFiles.addAll(['src/flserial.cpp', 'src/windows/dart_api_dl.c']);
    } else if (targetOS == OS.android) {
      // Android NDK zarządza stdlib automatycznie — nie dodawaj -lc++/-lstdc++
      customFlags.addAll(['-std=c++17', '-O2', '-fvisibility=default']);
      includeDirs.addAll(['src', 'src/linux']);
      srcFiles.addAll(['src/flserial.cpp', 'src/linux/dart_api_dl.cpp']);
    } else if (targetOS == OS.linux) {
      customFlags.addAll(['-std=c++17', '-O3', '-fvisibility=default', '-lstdc++']);
      includeDirs.addAll(['src', 'src/linux']);
      srcFiles.addAll(['src/flserial.cpp', 'src/linux/dart_api_dl.cpp']);
    } else if (targetOS == OS.macOS || targetOS == OS.iOS) {
      customFlags.addAll(['-std=c++17', '-O3', '-fvisibility=default', '-lc++']);
      includeDirs.addAll(['src', 'src/macos']);
      srcFiles.addAll(['src/flserial.cpp', 'src/macos/dart_api_dl.cpp']);
    } else {
      return;
    }

    final cbuilder = CBuilder.library(
      name: 'flserial',
      assetName: 'flserial',
      sources: srcFiles,
      includes: includeDirs,
      flags: customFlags,
    );

    await cbuilder.run(output: output, input: input);
  });
}
