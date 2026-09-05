# App icon

`AppIcon.png` is the source of truth. The same file is bundled as a target
resource and handed to the dock at launch; `OcarinaIcon` lays it on a
transparent canvas at the ~80% the macOS icon grid expects.

It is **120x120**. That is fine for the dock, which draws at 64pt, but soft
anywhere macOS asks for a large representation — Finder's Get Info, the app
switcher, the App Store. Replace it with a 1024px export when there is one;
nothing else needs to change.

To produce the `.icns` a packager wants:

```
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s   $s   AppIcon.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) AppIcon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset
```
