TERMINA DOT-MATRIX MAC APP ICON PACKAGE

FILES
-----
AppIcon.appiconset/
  Ready to drop into Xcode Assets.xcassets.

AppIcon.icns
  Useful for Electron, Tauri, native packaging tools, and older macOS build workflows.

AppIcon.iconset/
  Standard macOS iconset folder. Can be converted with:
  iconutil -c icns AppIcon.iconset

PNG/
  Standalone raster exports:
  16, 32, 64, 128, 256, 512, and 1024 px.

XCODE
-----
1. Open Assets.xcassets.
2. Delete or replace the existing AppIcon set.
3. Drag AppIcon.appiconset into Assets.xcassets.
4. In Target > General, make sure App Icons Source points to AppIcon.
5. Build and run.

ELECTRON
--------
Use AppIcon.icns as the macOS icon in your packager/build configuration.
Keep the 1024px PNG as the source/master asset.

TAURI
-----
Use the ICNS for macOS packaging, or run Tauri's icon generator using:
PNG/AppIcon-1024.png

APP STORE
---------
The macOS App Store icon is normally taken from the icon assets embedded in
the uploaded app build. Keep the 1024x1024 representation in the Xcode set.
