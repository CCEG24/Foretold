# Web URL switches

Diagnostic flags for the browser build. Add them to the page URL, and combine
them with `&`:

```
https://foretold.onrender.com/?log&nohover
http://localhost:8000/?webgpu&log
```

None of them are meant for players. Without any flags the page uses the
Canvas 2D renderer, with art, full resolution, and no debug UI.

| Switch | What it does | Where it's read |
| --- | --- | --- |
| `?log` | Shows the debug surfaces: the console mirror panel on the right, the green fps overlay in the top-left, and detailed error text. | `Web/index.html`, `WebMain.swift` (`WebFrameStats`) |
| `?webgpu` | Uses OpenSpriteKit's WebGPU renderer instead of Canvas 2D. Fails with a message if the browser has no GPU adapter. | `Web/index.html`, `WebMain.swift` |
| `?ss=N` | WebGPU only. Supersampling factor for antialiasing, default `2`, capped by `maxContentsScale`. `?ss=1` turns it off. | `WebMain.swift` (`CanvasConfig`) |
| `?noart` (or `#noart`) | Skips loading sprite PNGs, so bodies and weapons fall back to placeholder shapes. Useful for telling texture costs from scene costs. | `WebArt.swift` |
| `?nohover` | Ignores pointer movement entirely. Separates the game's hover work from the browser's own cost of pointer events. | `WebInput.swift` |
| `?dpr1` | Canvas 2D only. Renders the backing store at 1 pixel per CSS pixel instead of up to 2× on retina. | `Canvas2DRenderer.swift` |
| `?desync` | Canvas 2D only. Requests a `desynchronized` (low-latency) 2D context that presents outside the page's paint cycle. | `Canvas2DRenderer.swift` |

## Reading the `?log` overlay

```
60 fps · 1.0×
update 0.0ms  render 1.3ms
60 hovers 0.9ms  other 1132.0ms
art 7
2d/frame: 319 nodes  0 paths
2d/sec: 0 textures  0 measures  0 paths
```

- **fps · N×**: frames per second and the WebGPU contents scale. The scale
  always reads `1.0×` in Canvas 2D mode, where it doesn't apply.
- **update / render**: average milliseconds per frame spent in the scene
  update and in drawing.
- **hovers**: pointer-move events handled in the last second, and their total
  time.
- **other**: the rest of the second. This includes idle time, so a high value
  at 60 fps is normal. A high value at low fps means the time is going
  somewhere the overlay can't see, and you need a Chrome Performance
  recording to find it.
- **art**: how many sprites loaded.
- **2d/…** (Canvas 2D only): nodes drawn and shape paths rebuilt per frame,
  plus textures decoded, text measurements, and paths built per second.
  These should sit at or near 0 while nothing new is appearing.

## When the overlay isn't enough

Record a trace in Chrome:

1. Open DevTools and go to the Performance tab.
2. Record, reproduce the problem for a few seconds, then stop.
3. Right-click the timeline and choose **Save profile…**.

The sampled call stacks show which Swift function is hot. The hover slowdown
in Canvas 2D mode was found this way: Core Animation commits were capturing
GPU snapshots that nothing used (see `CATransaction.publishesRenderSnapshots`
in `patches/OpenCoreAnimation.patch`).
