#!/bin/bash

# 1. Znajdź ścieżkę do SDK Fluttera
FLUTTER_SDK=$(whereis flutter)

# 2. Ścieżka do nagłówków Dart Native API wewnątrz SDK
DART_INCLUDE_DIR="$FLUTTER_SDK/bin/cache/dart_sdk/include"

# 3. Sprawdź czy pliki istnieją
if [ -f "$DART_INCLUDE_DIR/dart_api_dl.h" ]; then
    echo "Znaleziono pliki w: $DART_INCLUDE_DIR"
    
    # Kopiowanie do Twojego folderu src
    cp "$DART_INCLUDE_DIR/dart_api_dl.h" ./src/
    cp "$DART_INCLUDE_DIR/dart_api_dl.c" ./src/
    
    echo "Sukces! Skopiowano dart_api_dl.h i dart_api_dl.c do ./src/"
else
    echo "BŁĄD: Nie znaleziono plików. Uruchom najpierw 'flutter precache'."
    exit 1
fi