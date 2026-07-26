# Third-party code and assets

## Notchy

Source: https://github.com/bones7456/notchy (a community fork of
https://github.com/adamlyttleapps/notchy)

License: MIT — Copyright (c) 2026 Adam Lyttle

Notchy is a macOS notch app that hosts Claude Code and Codex in an embedded
terminal. Its architecture differs from Hatchling's (it hosts the terminal;
we observe the user's own), but several self-contained pieces port cleanly.

Taken from it:

| What | Where in Hatchling |
|---|---|
| Notification sounds `taskCompleted.mp3` / `waitingForInput.mp3`, converted to WAV | `Sources/CodeIsland/Resources/notchy_complete.wav`, `notchy_approval.wav` |
| Microphone-activity check, to stay quiet during calls | `Sources/CodeIsland/MicrophoneActivityMonitor.swift` |
| Git checkpoint snapshots (orphan commit under a private ref, staged via a temp index) | `Sources/CodeIsland/CheckpointManager.swift` |
| Holding off idle system sleep while an agent is working | `AppState.updateSleepPrevention()` |

Adaptations we made: checkpoints supply their own git author identity so they
work in repos with no `user.name`/`user.email` configured, and read the process
pipes before waiting on exit to avoid a deadlock on large output; sound debounce
is per-sound rather than global, since Hatchling has more than two sounds and a
global gate would swallow distinct ones.

### MIT License (Notchy)

```
MIT License

Copyright (c) 2026 Adam Lyttle

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Upstream

Hatchling is a fork of [`wxtsky/CodeIsland`](https://github.com/wxtsky/CodeIsland) (MIT).
The Buddy ASCII data files inherit CC BY-NC 4.0 from MioIsland.
