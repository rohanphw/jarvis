# BUILD.md — Build a Meta Ray-Ban Smart Glasses AI Assistant (iOS)

> A step-by-step execution plan for building an iOS app that connects to Meta Ray-Ban smart glasses, streams their camera/audio, and pipes everything through a real-time LLM (Claude, GPT-4o, or Grok) for a voice+vision AI assistant.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Project Setup](#3-project-setup)
4. [Meta DAT SDK Integration](#4-meta-dat-sdk-integration)
5. [Core App Structure](#5-core-app-structure)
6. [Video Pipeline](#6-video-pipeline)
7. [Audio Pipeline](#7-audio-pipeline)
8. [LLM Integration (Pick Your Model)](#8-llm-integration-pick-your-model)
9. [Tool Calling / Agentic Layer](#9-tool-calling--agentic-layer)
10. [UI Layer](#10-ui-layer)
11. [iPhone Fallback Mode](#11-iphone-fallback-mode)
12. [Configuration & Secrets](#12-configuration--secrets)
13. [Testing Without Glasses](#13-testing-without-glasses)
14. [Build & Run](#14-build--run)
15. [Troubleshooting](#15-troubleshooting)
16. [File Manifest](#16-file-manifest)

---

## 1. Architecture Overview

```
Meta Ray-Ban Glasses (or iPhone camera fallback)
       │
       │  video frames (24fps from DAT SDK) + mic audio
       ▼
┌─────────────────────────────┐
│     iOS App (Swift/SwiftUI) │
│                             │
│  ┌─────────────────────┐    │
│  │  Video Pipeline     │    │
│  │  24fps → 1fps       │    │
│  │  → JPEG 50% quality │    │
│  │  → base64           │    │
│  └────────┬────────────┘    │
│           │                 │
│  ┌────────▼────────────┐    │
│  │  LLM Service        │    │  WebSocket / HTTP
│  │  (Claude / GPT /    │────┼──────────────────► LLM API
│  │   Grok)             │    │
│  └────────┬────────────┘    │
│           │                 │
│  ┌────────▼────────────┐    │
│  │  Audio Pipeline     │    │
│  │  Mic: PCM 16kHz     │    │
│  │  Speaker: PCM 24kHz │    │
│  └─────────────────────┘    │
│                             │
│  ┌─────────────────────┐    │
│  │  Tool Router        │────┼──► External tool gateway (optional)
│  │  (agentic actions)  │    │
│  └─────────────────────┘    │
└─────────────────────────────┘
```

**Key design decisions:**

- **Video throttling**: Raw 24fps from glasses → throttle to ~1fps before sending to LLM. Saves bandwidth, stays within LLM rate limits.
- **Audio format**: PCM Int16, mono. Input at 16kHz (mic), output at 24kHz (speaker). Accumulate into ~100ms chunks before sending.
- **Audio session modes**: `.voiceChat` for iPhone mode (aggressive echo cancellation when mic and speaker are co-located), `.videoChat` for glasses mode (mic on glasses, speaker on phone — no echo loop).
- **Dual streaming modes**: Glasses mode uses DAT SDK; iPhone mode uses `AVCaptureSession` as a fallback for development.

---

## 2. Prerequisites

| Requirement | Details |
|-------------|---------|
| **macOS** | Ventura 13.0+ (for Xcode 15+) |
| **Xcode** | 15.0+ with iOS 17 SDK |
| **iOS device** | iPhone running iOS 17.0+ (simulator won't work — needs Bluetooth + camera) |
| **Apple Developer Account** | Free account works for development; paid for distribution |
| **Meta Ray-Ban glasses** | Any model with camera (Ray-Ban Meta Wayfarer, Headliner, etc.) — *optional for dev, use iPhone mode* |
| **Meta AI app** | Installed on your iPhone, with Developer Mode enabled |
| **LLM API key** | One of: Anthropic (Claude), OpenAI (GPT-4o), or xAI (Grok) |
| **Meta Wearables Developer Center account** | Register at [wearables.developer.meta.com](https://wearables.developer.meta.com) — needed for production, optional with Developer Mode |

### Install Xcode CLI tools

```bash
xcode-select --install
```

---

## 3. Project Setup

### 3.1 Create the Xcode project

```
File → New → Project → App
  Product Name: GlassesAI
  Team: (your dev team)
  Organization Identifier: com.yourname
  Interface: SwiftUI
  Language: Swift
  Minimum Deployment: iOS 17.0
```

### 3.2 Add the Meta DAT SDK via Swift Package Manager

```
File → Add Package Dependencies...
  URL: https://github.com/facebook/meta-wearables-dat-ios
  Version: Exact → 0.4.0
```

Add these three products to your target:

- `MWDATCore` — core SDK (registration, permissions, device discovery)
- `MWDATCamera` — camera streaming, video frames, photo capture
- `MWDATMockDevice` — mock devices for testing (DEBUG only)

### 3.3 Configure `Info.plist`

These entries are **mandatory** for the DAT SDK to function:

```xml
<!-- Meta Wearables DAT SDK Configuration -->
<key>MWDAT</key>
<dict>
    <key>AppLinkURLScheme</key>
    <string>glassesai://</string>
    <key>MetaAppID</key>
    <string>$(META_APP_ID)</string>
    <key>ClientToken</key>
    <string>$(CLIENT_TOKEN)</string>
    <key>TeamID</key>
    <string>$(DEVELOPMENT_TEAM)</string>
</dict>

<!-- Required background modes for BLE connection to glasses -->
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
    <string>external-accessory</string>
</array>

<!-- Privacy descriptions -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta smart glasses</string>
<key>NSCameraUsageDescription</key>
<string>Used for iPhone testing mode without glasses</string>
<key>NSMicrophoneUsageDescription</key>
<string>Used for voice conversations with the AI assistant</string>

<!-- External accessory protocol for Meta glasses -->
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.meta.ar.wearable</string>
</array>

<!-- Allow local networking for tool gateway -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>

<!-- URL scheme for Meta AI app callback -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>glassesai</string>
        </array>
    </dict>
</array>
```

### 3.4 Entitlements

Create `GlassesAI.entitlements` — can be empty dict initially:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

---

## 4. Meta DAT SDK Integration

### 4.1 SDK Initialization (App Entry Point)

```swift
// GlassesAIApp.swift
import SwiftUI
import MWDATCore
#if DEBUG
import MWDATMockDevice
#endif

@main
struct GlassesAIApp: App {
    init() {
        do {
            try Wearables.configure()
        } catch {
            NSLog("[GlassesAI] SDK configure failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Key point**: `Wearables.configure()` must be called once at launch before any SDK usage. `Wearables.shared` is the singleton you use everywhere after that.

### 4.2 Registration Flow

The user must "register" (authorize) via the Meta AI companion app. This is an OAuth-like flow:

```swift
// Start registration — opens Meta AI app
try await Wearables.shared.startRegistration()

// Handle the callback URL when Meta AI redirects back
// In your root view:
.onOpenURL { url in
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
    else { return }
    Task {
        _ = try await Wearables.shared.handleUrl(url)
    }
}
```

**Registration states** you'll observe:

```swift
for await state in Wearables.shared.registrationStateStream() {
    switch state {
    case .registered:    // Good to go
    case .registering:   // In progress (user is in Meta AI app)
    case .unregistered:  // Need to register
    }
}
```

### 4.3 Device Discovery

```swift
// Stream of available device identifiers
for await devices in Wearables.shared.devicesStream() {
    // devices: [DeviceIdentifier]
    for id in devices {
        if let device = Wearables.shared.deviceForIdentifier(id) {
            let compat = device.compatibility()
            // Check: .compatible, .deviceUpdateRequired, etc.
        }
    }
}
```

### 4.4 Camera Permissions

```swift
let status = try await Wearables.shared.checkPermissionStatus(.camera)
if status != .granted {
    let result = try await Wearables.shared.requestPermission(.camera)
    // This opens Meta AI app for the user to grant permission
}
```

### 4.5 Streaming Session

```swift
import MWDATCamera

let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)

let config = StreamSessionConfig(
    videoCodec: .raw,
    resolution: .low,      // Use .low for AI processing (saves bandwidth)
    frameRate: 24
)

let session = StreamSession(
    streamSessionConfig: config,
    deviceSelector: deviceSelector
)

// Listen for video frames
session.videoFramePublisher.listen { videoFrame in
    if let image = videoFrame.makeUIImage() {
        // You have a UIImage from the glasses camera
    }
}

// Listen for state changes
session.statePublisher.listen { state in
    // .stopped, .waitingForDevice, .starting, .streaming, .paused, .stopping
}

// Listen for errors
session.errorPublisher.listen { error in
    // .deviceNotFound, .deviceNotConnected, .timeout,
    // .videoStreamingError, .permissionDenied, .hingesClosed, etc.
}

// Start/stop
await session.start()
await session.stop()

// Photo capture
session.capturePhoto(format: .jpeg)
session.photoDataPublisher.listen { photoData in
    let image = UIImage(data: photoData.data)
}
```

---

## 5. Core App Structure

### Directory layout

```
GlassesAI/
├── GlassesAIApp.swift              # Entry point, SDK init
├── Secrets.swift                    # API keys (gitignored)
├── Secrets.swift.example            # Template for secrets
├── Info.plist
├── GlassesAI.entitlements
│
├── LLM/                            # LLM integration layer
│   ├── LLMConfig.swift             # Model config, API endpoints
│   ├── LLMService.swift            # WebSocket/HTTP client
│   ├── LLMSessionViewModel.swift   # Session lifecycle, UI state
│   └── AudioManager.swift          # Mic capture + audio playback
│
├── Tools/                           # Tool calling / agentic layer
│   ├── ToolCallModels.swift        # Data models for tool calls
│   ├── ToolBridge.swift            # HTTP client for tool gateway
│   └── ToolCallRouter.swift        # Routes LLM tool calls to bridge
│
├── iPhone/                          # iPhone camera fallback
│   └── IPhoneCameraManager.swift   # AVCaptureSession wrapper
│
├── ViewModels/
│   ├── StreamSessionViewModel.swift # DAT SDK streaming state
│   └── WearablesViewModel.swift     # Registration, device state
│
└── Views/
    ├── MainAppView.swift            # Navigation hub
    ├── HomeScreenView.swift         # Registration/onboarding
    ├── StreamSessionView.swift      # Streaming container
    ├── StreamView.swift             # Active streaming UI
    ├── NonStreamView.swift          # Pre-streaming setup
    └── Components/
        ├── LLMOverlayView.swift     # Status pills, transcripts
        ├── CircleButton.swift
        └── CustomButton.swift
```

---

## 6. Video Pipeline

### 6.1 Frame capture from glasses

The DAT SDK delivers frames at the configured frame rate (24fps). You **must** throttle before sending to any LLM.

```swift
// In your session view model:
private var lastVideoFrameTime: Date = .distantPast
private let frameInterval: TimeInterval = 1.0  // 1fps to LLM

func processVideoFrame(image: UIImage) {
    let now = Date()
    guard now.timeIntervalSince(lastVideoFrameTime) >= frameInterval else { return }
    lastVideoFrameTime = now

    // Convert to JPEG, base64 encode, send to LLM
    guard let jpegData = image.jpegData(compressionQuality: 0.5) else { return }
    let base64 = jpegData.base64EncodedString()
    llmService.sendImage(base64: base64, mimeType: "image/jpeg")
}
```

### 6.2 Why ~1fps and 50% JPEG?

- **1fps** is enough for scene understanding. More frames waste tokens/bandwidth with near-identical content.
- **50% JPEG** gives ~30-60KB per frame. At 1fps, that's ~30-60KB/s — manageable over WebSocket.
- The LLM doesn't need 24fps video — it needs periodic visual context snapshots.

---

## 7. Audio Pipeline

### 7.1 AudioManager implementation

This is the most complex piece. You need bidirectional audio: mic → LLM, and LLM → speaker.

```swift
class AudioManager {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isCapturing = false
    var onAudioCaptured: ((Data) -> Void)?

    // Accumulate resampled PCM into ~100ms chunks before sending
    private let sendQueue = DispatchQueue(label: "audio.accumulator")
    private var accumulatedData = Data()
    private let minSendBytes = 3200  // 100ms at 16kHz mono Int16

    func setupAudioSession(useIPhoneMode: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        // iPhone mode: .voiceChat for aggressive echo cancellation
        // Glasses mode: .videoChat (mic on glasses, speaker on phone)
        let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat
        try session.setCategory(.playAndRecord, mode: mode,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(16000)
        try session.setPreferredIOBufferDuration(0.064)
        try session.setActive(true)
    }

    func startCapture() throws {
        // 1. Attach playerNode for output
        audioEngine.attach(playerNode)
        let playerFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 24000, channels: 1,
                                         interleaved: false)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

        // 2. Tap input in native format, resample to 16kHz Int16
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Set up AVAudioConverter if native rate ≠ 16kHz
        var converter: AVAudioConverter?
        if nativeFormat.sampleRate != 16000 || nativeFormat.channelCount != 1 {
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16000, channels: 1,
                                             interleaved: false)!
            converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            let pcmData: Data
            if let converter {
                guard let resampled = self.resample(buffer, using: converter) else { return }
                pcmData = self.float32ToInt16(resampled)
            } else {
                pcmData = self.float32ToInt16(buffer)
            }

            // Accumulate into ~100ms chunks
            self.sendQueue.async {
                self.accumulatedData.append(pcmData)
                if self.accumulatedData.count >= self.minSendBytes {
                    let chunk = self.accumulatedData
                    self.accumulatedData = Data()
                    self.onAudioCaptured?(chunk)
                }
            }
        }

        try audioEngine.start()
        playerNode.play()
        isCapturing = true
    }

    func playAudio(data: Data) {
        // Convert Int16 PCM data to Float32 buffer and schedule on playerNode
        let frameCount = UInt32(data.count / 2)  // Int16 = 2 bytes per frame
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: 24000, channels: 1,
                                    interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { raw in
            guard let int16Ptr = raw.bindMemory(to: Int16.self).baseAddress,
                  let floatData = buffer.floatChannelData else { return }
            for i in 0..<Int(frameCount) {
                floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stopPlayback() {
        playerNode.stop()
        playerNode.play()  // Reset for next playback
    }

    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        audioEngine.detach(playerNode)
        isCapturing = false
    }
}
```

### 7.2 Echo cancellation strategy

| Mode | Audio Session | Why |
|------|---------------|-----|
| **iPhone** | `.voiceChat` | Mic and speaker are on the same device. iOS's aggressive AEC is needed. Also mute mic while model speaks. |
| **Glasses** | `.videoChat` | Mic is on glasses (over BLE), speaker is on phone. No acoustic coupling, so mild AEC suffices. |

---

## 8. LLM Integration (Pick Your Model)

This is where you choose your backend. Below are three options — implement **one** (or make it configurable).

### Option A: Anthropic Claude (claude-sonnet-4-5-20250929)

Claude doesn't have a native real-time audio WebSocket API like Gemini. You'll use the **Messages API** with vision, and handle TTS/STT separately.

```swift
// Architecture for Claude:
// Mic Audio → Apple Speech (on-device STT) → text
// Text + JPEG frame → Claude Messages API → response text
// Response text → AVSpeechSynthesizer (on-device TTS) → speaker

class ClaudeLLMService {
    private let apiKey: String
    private let model = "claude-sonnet-4-5-20250929"
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private var conversationHistory: [[String: Any]] = []

    func sendMessage(text: String, imageBase64: String?) async throws -> String {
        var content: [[String: Any]] = []

        // Add image if available
        if let img = imageBase64 {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": img
                ]
            ])
        }

        content.append(["type": "text", "text": text])

        conversationHistory.append(["role": "user", "content": content])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": conversationHistory
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let contentBlocks = json["content"] as! [[String: Any]]
        let responseText = contentBlocks.compactMap { $0["text"] as? String }.joined()

        conversationHistory.append(["role": "assistant", "content": responseText])
        return responseText
    }
}
```

**For Claude, you also need:**

```swift
// On-device STT (Speech → Text)
import Speech

class SpeechRecognizer {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func startListening(onResult: @escaping (String, Bool) -> Void) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            }
        }

        try? audioEngine.start()
    }
}

// On-device TTS (Text → Speech)
import AVFoundation

class SpeechSynthesizer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        synthesizer.speak(utterance)
    }
}
```

**Pros**: Best reasoning, best tool use, great vision. **Cons**: No native real-time audio — requires on-device STT/TTS, adding ~500ms latency.

### Option B: OpenAI GPT-4o Realtime API

OpenAI has a **Realtime API** with native audio over WebSocket — closest to the Gemini approach used in the reference codebase.

```swift
class GPTRealtimeLLMService {
    private var webSocket: URLSessionWebSocketTask?
    private let model = "gpt-4o-realtime-preview"
    var onAudioReceived: ((Data) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onToolCall: ((ToolCall) -> Void)?

    func connect(apiKey: String) async -> Bool {
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()

        // Send session config
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": systemPrompt,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "whisper-1"],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "silence_duration_ms": 500
                ],
                "tools": toolDeclarations
            ]
        ]
        sendJSON(config)
        startReceiving()
        return true
    }

    func sendAudio(data: Data) {
        let base64 = data.base64EncodedString()
        sendJSON([
            "type": "input_audio_buffer.append",
            "audio": base64
        ])
    }

    func sendImage(base64: String) {
        // GPT-4o Realtime: send as a conversation item with image
        sendJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_image", "image_url": "data:image/jpeg;base64,\(base64)"]
                ]
            ]
        ])
    }

    // Handle incoming messages: response.audio.delta, response.text.delta,
    // response.function_call_arguments.delta, etc.
}
```

**Pros**: Native real-time audio, low latency, good vision. **Cons**: Expensive, vision in realtime API may have limitations.

### Option C: xAI Grok

Grok's API is OpenAI-compatible. Use the standard chat completions endpoint with vision. Similar to the Claude approach (STT → text+image → API → TTS).

```swift
class GrokLLMService {
    private let apiKey: String
    private let baseURL = "https://api.x.ai/v1/chat/completions"
    private let model = "grok-2-vision-1212"  // or latest
    private var messages: [[String: Any]] = []

    func sendMessage(text: String, imageBase64: String?) async throws -> String {
        var content: [[String: Any]] = []
        if let img = imageBase64 {
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(img)"]
            ])
        }
        content.append(["type": "text", "text": text])
        messages.append(["role": "user", "content": content])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        // Parse OpenAI-compatible response
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choices = json["choices"] as! [[String: Any]]
        let message = choices[0]["message"] as! [String: Any]
        let responseText = message["content"] as! String

        messages.append(["role": "assistant", "content": responseText])
        return responseText
    }
}
```

**Pros**: Fast, uncensored, OpenAI-compatible. **Cons**: No native real-time audio API — needs STT/TTS like Claude.

### Comparison Matrix

| Feature | Claude (Anthropic) | GPT-4o Realtime (OpenAI) | Grok (xAI) |
|---------|-------------------|-------------------------|-------------|
| Native real-time audio | ❌ (use on-device STT/TTS) | ✅ WebSocket | ❌ (use on-device STT/TTS) |
| Vision quality | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| Tool calling | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| Latency (audio round-trip) | ~1-2s (STT+API+TTS) | ~300-500ms (native) | ~1-2s (STT+API+TTS) |
| Cost | Medium | High | Low |
| Reasoning | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |

**Recommendation**: If latency matters most → **GPT-4o Realtime**. If reasoning/tool-use quality matters most → **Claude**. If cost matters most → **Grok**.

---

## 9. Tool Calling / Agentic Layer

### 9.1 Tool declaration pattern

Declare a single `execute` tool that routes all actions through an external gateway:

```swift
// For Claude:
let tools: [[String: Any]] = [[
    "name": "execute",
    "description": "Execute any real-world action: send messages, search web, manage lists, etc.",
    "input_schema": [
        "type": "object",
        "properties": [
            "task": [
                "type": "string",
                "description": "Detailed description of the task to perform"
            ]
        ],
        "required": ["task"]
    ]
]]

// For GPT-4o / Grok (OpenAI format):
let tools: [[String: Any]] = [[
    "type": "function",
    "function": [
        "name": "execute",
        "description": "Execute any real-world action: send messages, search web, manage lists, etc.",
        "parameters": [
            "type": "object",
            "properties": [
                "task": ["type": "string", "description": "Detailed task description"]
            ],
            "required": ["task"]
        ]
    ]
]]
```

### 9.2 Tool call router

```swift
@MainActor
class ToolCallRouter {
    private let bridge: ToolBridge
    private var inFlightTasks: [String: Task<Void, Never>] = [:]

    func handleToolCall(_ call: FunctionCall, sendResponse: @escaping ([String: Any]) -> Void) {
        let task = Task { @MainActor in
            let result = await bridge.delegateTask(task: call.args["task"] as? String ?? "")

            guard !Task.isCancelled else { return }

            sendResponse(buildResponse(callId: call.id, result: result))
            inFlightTasks.removeValue(forKey: call.id)
        }
        inFlightTasks[call.id] = task
    }

    func cancelToolCalls(ids: [String]) {
        for id in ids {
            inFlightTasks[id]?.cancel()
            inFlightTasks.removeValue(forKey: id)
        }
    }
}
```

### 9.3 Tool bridge (HTTP to external gateway)

```swift
class ToolBridge {
    private let gatewayURL: String
    private let token: String
    private var sessionKey: String
    private var history: [[String: String]] = []

    func delegateTask(task: String) async -> ToolResult {
        history.append(["role": "user", "content": task])

        var request = URLRequest(url: URL(string: gatewayURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionKey, forHTTPHeaderField: "x-session-key")

        let body: [String: Any] = [
            "model": "agent",
            "messages": history,
            "stream": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // Parse response, append to history, return result
            // ...
            return .success(resultText)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
```

---

## 10. UI Layer

### 10.1 Key views

**StreamView** — the main streaming experience:

```swift
struct StreamView: View {
    @ObservedObject var streamVM: StreamSessionViewModel
    @ObservedObject var llmVM: LLMSessionViewModel

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // Video feed (full screen)
            if let frame = streamVM.currentVideoFrame {
                GeometryReader { geo in
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .edgesIgnoringSafeArea(.all)
            }

            // LLM status overlay
            if llmVM.isActive {
                VStack {
                    StatusBar(llmVM: llmVM)
                    Spacer()
                    TranscriptOverlay(user: llmVM.userTranscript, ai: llmVM.aiTranscript)
                    if llmVM.isModelSpeaking {
                        SpeakingIndicator()
                    }
                }
                .padding()
            }

            // Bottom controls
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    // Stop streaming button
                    // Photo capture button (glasses mode only)
                    // AI toggle button
                }
            }
            .padding()
        }
    }
}
```

### 10.2 Status indicators

Use colored pills to show connection state:

```swift
struct StatusPill: View {
    let color: Color  // .green = connected, .yellow = connecting, .red = error, .gray = off
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(16)
    }
}
```

### 10.3 Speaking indicator (animated bars)

```swift
struct SpeakingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white)
                    .frame(width: 3, height: animating ? CGFloat.random(in: 8...20) : 6)
                    .animation(.easeInOut(duration: 0.3).repeatForever().delay(Double(i) * 0.1),
                               value: animating)
            }
        }
        .onAppear { animating = true }
    }
}
```

---

## 11. iPhone Fallback Mode

For development without glasses, use the iPhone's back camera:

```swift
class IPhoneCameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "iphone-camera")
    private let context = CIContext()
    var onFrameCaptured: ((UIImage) -> Void)?

    func start() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .medium

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.captureSession.canAddInput(input) else { return }
            self.captureSession.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)
            output.alwaysDiscardsLateVideoFrames = true
            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
            }

            // Fix rotation to portrait
            if let conn = output.connection(with: .video),
               conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from conn: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        onFrameCaptured?(UIImage(cgImage: cgImage))
    }
}
```

---

## 12. Configuration & Secrets

### Secrets.swift.example (commit this)

```swift
import Foundation

enum Secrets {
    // Pick ONE LLM provider and fill in its key:

    // Option A: Anthropic Claude
    static let anthropicAPIKey = "YOUR_ANTHROPIC_API_KEY"

    // Option B: OpenAI GPT-4o
    static let openAIAPIKey = "YOUR_OPENAI_API_KEY"

    // Option C: xAI Grok
    static let xAIAPIKey = "YOUR_XAI_API_KEY"

    // OPTIONAL: Tool gateway config
    static let toolGatewayHost = "http://YOUR_MAC_HOSTNAME.local"
    static let toolGatewayPort = 18789
    static let toolGatewayToken = "YOUR_GATEWAY_TOKEN"
}
```

### .gitignore

```
*.xcframework/
.DS_Store
xcuserdata/
*.xcworkspace/
Secrets.swift
```

---

## 13. Testing Without Glasses

### Enable Developer Mode in Meta AI app

1. Open **Meta AI** app
2. Go to **Settings** (gear icon)
3. Tap **App Info**
4. Tap the **App version number 5 times** — unlocks Developer Mode
5. Go back to Settings → toggle **Developer Mode** on

With Developer Mode, you don't need a Wearables Developer Center registration. The `MetaAppID` and `ClientToken` in Info.plist can use placeholder values.

### Use Mock Devices (DEBUG builds)

```swift
#if DEBUG
import MWDATMockDevice

// Create a mock pair of glasses
let mockDevice = MockDeviceKit.shared.pairRaybanMeta()
mockDevice.powerOn()
mockDevice.unfold()

// Load mock video feed
if let cameraKit = mockDevice.getCameraKit() {
    await cameraKit.setCameraFeed(fileURL: videoURL)
    await cameraKit.setCapturedImage(fileURL: imageURL)
}
#endif
```

### Use iPhone Camera Mode

The simplest path: just use the iPhone's back camera. No glasses, no DAT SDK needed. Point your phone at things and talk to the AI.

---

## 14. Build & Run

```bash
# 1. Clone your project
git clone https://github.com/yourname/GlassesAI.git
cd GlassesAI

# 2. Create your secrets file
cp Secrets.swift.example Secrets.swift
# Edit Secrets.swift with your API key

# 3. Open in Xcode
open GlassesAI.xcodeproj

# 4. Select your iPhone as target device (not simulator)
# 5. Cmd+R to build and run
```

### First run checklist

- [ ] Xcode signing: set your team under Signing & Capabilities
- [ ] Connected iPhone running iOS 17+
- [ ] Secrets.swift has a valid LLM API key
- [ ] Grant camera + microphone permissions when prompted
- [ ] For glasses: Meta AI app installed with Developer Mode enabled

---

## 15. Troubleshooting

| Problem | Solution |
|---------|----------|
| `Wearables.configure()` crashes | Ensure DAT SDK v0.4.0 and all Info.plist keys are set |
| No devices appear | Check Bluetooth is on, glasses are powered on and unfolded, Meta AI app has Developer Mode |
| Permission denied | Permission flow goes through Meta AI app. Ensure the callback URL scheme matches Info.plist |
| Echo / feedback in iPhone mode | App should mute mic while model speaks. Check audio session is `.voiceChat` |
| LLM doesn't respond | Check API key, check network, check console logs for HTTP errors |
| Video frames not reaching LLM | Check throttle timer, check connection state is `.ready` before sending |
| Audio playback glitches | Ensure `playerNode.play()` is called, check audio format matches (24kHz Int16 mono) |
| `hingesClosed` error | Open the glasses hinges (arms). Streaming requires open hinges. |

---

## 16. File Manifest

Final project structure with all files:

```
GlassesAI/
├── GlassesAI.xcodeproj/
├── GlassesAI/
│   ├── GlassesAIApp.swift                    # App entry, SDK init
│   ├── Info.plist                             # DAT SDK config, permissions, URL scheme
│   ├── GlassesAI.entitlements
│   ├── Assets.xcassets/                       # App icon, colors
│   ├── Secrets.swift                          # YOUR API KEYS (gitignored)
│   ├── Secrets.swift.example                  # Template (committed)
│   │
│   ├── LLM/
│   │   ├── LLMConfig.swift                   # Model name, endpoints, system prompt
│   │   ├── LLMService.swift                  # API client (WebSocket or HTTP)
│   │   ├── LLMSessionViewModel.swift         # Session state, audio/video wiring
│   │   └── AudioManager.swift                # AVAudioEngine mic capture + playback
│   │
│   ├── Tools/
│   │   ├── ToolCallModels.swift              # FunctionCall, ToolResult, ToolCallStatus
│   │   ├── ToolBridge.swift                  # HTTP client for external tool gateway
│   │   └── ToolCallRouter.swift              # Routes LLM tool calls → bridge
│   │
│   ├── iPhone/
│   │   └── IPhoneCameraManager.swift         # AVCaptureSession fallback camera
│   │
│   ├── ViewModels/
│   │   ├── StreamSessionViewModel.swift      # DAT SDK streaming lifecycle
│   │   ├── WearablesViewModel.swift          # Registration, device discovery
│   │   └── MockDeviceKit/ (DEBUG only)
│   │       ├── MockDeviceKitViewModel.swift
│   │       └── MockDeviceViewModel.swift
│   │
│   └── Views/
│       ├── MainAppView.swift                 # Registered → stream, else → onboard
│       ├── HomeScreenView.swift              # Registration UI
│       ├── StreamSessionView.swift           # Container: streaming vs non-streaming
│       ├── StreamView.swift                  # Active stream + AI overlay + controls
│       ├── NonStreamView.swift               # Pre-stream setup, start buttons
│       ├── RegistrationView.swift            # Invisible URL handler for Meta AI callback
│       ├── PhotoPreviewView.swift            # Photo capture preview + share
│       └── Components/
│           ├── LLMOverlayView.swift          # Status pills, transcripts, speaking indicator
│           ├── CircleButton.swift
│           ├── CustomButton.swift
│           ├── CardView.swift
│           └── StatusText.swift
│
├── GlassesAITests/
│   └── IntegrationTests.swift               # Mock device streaming + capture tests
│
├── .gitignore
└── README.md
```

---

## Appendix A: Copy-Paste Production Code for Meta Glasses

> Every file below is **production-ready** code extracted and adapted from the reference codebase. Copy each file into the indicated path in your Xcode project. The only changes you need to make are marked with `// TODO: CHANGE THIS`.

---

### A.1 — Complete `Info.plist`

> **File**: `GlassesAI/Info.plist`
> This is the full, exact plist. Copy it wholesale and only change the URL scheme if you rename the app.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>${PRODUCT_NAME}</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>GlassesAI</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLName</key>
			<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<!-- TODO: CHANGE THIS if you rename the app -->
				<string>glassesai</string>
			</array>
		</dict>
	</array>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>

	<!-- ========== META WEARABLES DAT SDK — REQUIRED ========== -->
	<key>MWDAT</key>
	<dict>
		<key>AppLinkURLScheme</key>
		<!-- Must match CFBundleURLSchemes above, with :// suffix -->
		<string>glassesai://</string>
		<key>MetaAppID</key>
		<!-- Get from Wearables Developer Center. Placeholder OK with Developer Mode. -->
		<string>$(META_APP_ID)</string>
		<key>ClientToken</key>
		<!-- Get from Wearables Developer Center. Placeholder OK with Developer Mode. -->
		<string>$(CLIENT_TOKEN)</string>
		<key>TeamID</key>
		<!-- Your Apple Developer Team ID (auto-set from Signing & Capabilities) -->
		<string>$(DEVELOPMENT_TEAM)</string>
	</dict>

	<key>UIBackgroundModes</key>
	<array>
		<string>bluetooth-peripheral</string>
		<string>external-accessory</string>
	</array>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Needed to connect to Meta AI Glasses</string>
	<key>UISupportedExternalAccessoryProtocols</key>
	<array>
		<string>com.meta.ar.wearable</string>
	</array>
	<!-- ========== END DAT SDK REQUIRED SECTION ========== -->

	<key>NSCameraUsageDescription</key>
	<string>This app uses the camera for iPhone testing mode, allowing you to test the AI assistant pipeline without glasses.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>This app uses the microphone to have voice conversations with the AI assistant while streaming from your glasses.</string>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>This app needs access to save photos captured from your glasses.</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
	</dict>
	<key>UIApplicationSupportsIndirectInputEvents</key>
	<true/>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UIRequiredDeviceCapabilities</key>
	<array>
		<string>armv7</string>
	</array>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
```

---

### A.2 — App Entry Point (SDK Init + Full Wiring)

> **File**: `GlassesAI/GlassesAIApp.swift`

```swift
import Foundation
import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct GlassesAIApp: App {
    #if DEBUG
    @StateObject private var debugMenuViewModel = DebugMenuViewModel(mockDeviceKit: MockDeviceKit.shared)
    #endif
    private let wearables: WearablesInterface
    @StateObject private var wearablesViewModel: WearablesViewModel

    init() {
        // CRITICAL: Must call configure() once before any SDK usage.
        // This reads Info.plist MWDAT keys and initializes BLE scanning.
        do {
            try Wearables.configure()
        } catch {
            #if DEBUG
            NSLog("[GlassesAI] Failed to configure Wearables SDK: \(error)")
            #endif
        }
        let wearables = Wearables.shared
        self.wearables = wearables
        self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
    }

    var body: some Scene {
        WindowGroup {
            MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
                .alert("Error", isPresented: $wearablesViewModel.showError) {
                    Button("OK") { wearablesViewModel.dismissError() }
                } message: {
                    Text(wearablesViewModel.errorMessage)
                }
                #if DEBUG
                .sheet(isPresented: $debugMenuViewModel.showDebugMenu) {
                    MockDeviceKitView(viewModel: debugMenuViewModel.mockDeviceKitViewModel)
                }
                .overlay {
                    DebugMenuView(debugMenuViewModel: debugMenuViewModel)
                }
                #endif

            // This invisible view catches the callback URL from Meta AI app
            RegistrationView(viewModel: wearablesViewModel)
        }
    }
}
```

---

### A.3 — WearablesViewModel (Registration + Device Discovery + Compatibility Monitoring)

> **File**: `GlassesAI/ViewModels/WearablesViewModel.swift`
> This is the **complete** view model that manages the entire DAT SDK lifecycle.

```swift
import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@MainActor
class WearablesViewModel: ObservableObject {
    @Published var devices: [DeviceIdentifier]
    @Published var hasMockDevice: Bool
    @Published var registrationState: RegistrationState
    @Published var showGettingStartedSheet: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?
    private var setupDeviceStreamTask: Task<Void, Never>?
    private let wearables: WearablesInterface
    private var compatibilityListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]

    init(wearables: WearablesInterface) {
        self.wearables = wearables
        self.devices = wearables.devices
        self.hasMockDevice = false
        self.registrationState = wearables.registrationState

        // Start listening for device events immediately
        setupDeviceStreamTask = Task {
            await setupDeviceStream()
        }

        // Listen for registration state changes (registering → registered → unregistered)
        registrationTask = Task {
            for await registrationState in wearables.registrationStateStream() {
                let previousState = self.registrationState
                self.registrationState = registrationState
                // Show onboarding sheet when registration completes
                if self.showGettingStartedSheet == false
                    && registrationState == .registered
                    && previousState == .registering {
                    self.showGettingStartedSheet = true
                }
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
        setupDeviceStreamTask?.cancel()
    }

    // MARK: - Device Stream (live list of paired devices)

    private func setupDeviceStream() async {
        if let task = deviceStreamTask, !task.isCancelled { task.cancel() }

        deviceStreamTask = Task {
            // devicesStream() is an AsyncSequence that emits whenever a device
            // connects, disconnects, or changes state
            for await devices in wearables.devicesStream() {
                self.devices = devices
                #if DEBUG
                self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
                #endif
                monitorDeviceCompatibility(devices: devices)
            }
        }
    }

    // MARK: - Compatibility Monitoring

    private func monitorDeviceCompatibility(devices: [DeviceIdentifier]) {
        let deviceSet = Set(devices)
        // Remove listeners for devices that are no longer present
        compatibilityListenerTokens = compatibilityListenerTokens.filter { deviceSet.contains($0.key) }

        for deviceId in devices {
            guard compatibilityListenerTokens[deviceId] == nil else { continue }
            guard let device = wearables.deviceForIdentifier(deviceId) else { continue }

            let deviceName = device.nameOrId()
            // addCompatibilityListener fires whenever the device's firmware/SDK
            // compatibility changes (e.g., after a firmware update)
            let token = device.addCompatibilityListener { [weak self] compatibility in
                guard let self else { return }
                if compatibility == .deviceUpdateRequired {
                    Task { @MainActor in
                        self.showError("Device '\(deviceName)' requires an update to work with this app")
                    }
                }
            }
            compatibilityListenerTokens[deviceId] = token
        }
    }

    // MARK: - Registration (Connect / Disconnect Glasses)

    /// Opens the Meta AI app for the user to authorize this app.
    /// The result comes back via RegistrationView's .onOpenURL handler.
    func connectGlasses() {
        guard registrationState != .registering else { return }
        Task { @MainActor in
            do {
                try await wearables.startRegistration()
            } catch let error as RegistrationError {
                showError(error.description)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    /// Disconnects from glasses and revokes registration.
    func disconnectGlasses() {
        Task { @MainActor in
            do {
                try await wearables.startUnregistration()
            } catch let error as UnregistrationError {
                showError(error.description)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func showError(_ error: String) {
        errorMessage = error
        showError = true
    }

    func dismissError() {
        showError = false
    }
}
```

---

### A.4 — RegistrationView (URL Callback Handler)

> **File**: `GlassesAI/Views/RegistrationView.swift`
> This invisible view **must** be in your view hierarchy. It catches the OAuth callback from Meta AI.

```swift
import MWDATCore
import SwiftUI

struct RegistrationView: View {
    @ObservedObject var viewModel: WearablesViewModel

    var body: some View {
        EmptyView()
            // This .onOpenURL catches the deep link from Meta AI app after
            // the user approves registration or grants camera permission.
            .onOpenURL { url in
                guard
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                    // Only handle URLs that contain the DAT SDK action parameter
                    components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
                else {
                    return  // Not a DAT SDK URL — ignore
                }
                Task {
                    do {
                        // handleUrl() completes the registration or permission flow.
                        // The SDK parses the URL, extracts tokens, and updates state.
                        _ = try await Wearables.shared.handleUrl(url)
                    } catch let error as RegistrationError {
                        viewModel.showError(error.description)
                    } catch {
                        viewModel.showError("Unknown error: \(error.localizedDescription)")
                    }
                }
            }
    }
}
```

---

### A.5 — StreamSessionViewModel (Complete Streaming Lifecycle)

> **File**: `GlassesAI/ViewModels/StreamSessionViewModel.swift`
> This is the **heart** of the glasses integration — device selection, permissions, streaming, frames, photos, errors, and iPhone fallback.

```swift
import MWDATCamera
import MWDATCore
import SwiftUI

enum StreamingStatus {
    case streaming
    case waiting
    case stopped
}

enum StreamingMode {
    case glasses
    case iPhone
}

@MainActor
class StreamSessionViewModel: ObservableObject {
    @Published var currentVideoFrame: UIImage?
    @Published var hasReceivedFirstFrame: Bool = false
    @Published var streamingStatus: StreamingStatus = .stopped
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var hasActiveDevice: Bool = false
    @Published var streamingMode: StreamingMode = .glasses

    var isStreaming: Bool { streamingStatus != .stopped }

    // Photo capture
    @Published var capturedPhoto: UIImage?
    @Published var showPhotoPreview: Bool = false

    // TODO: Wire your LLM session view model here
    // var llmSessionVM: LLMSessionViewModel?

    // DAT SDK objects
    private var streamSession: StreamSession
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private var photoDataListenerToken: AnyListenerToken?
    private let wearables: WearablesInterface
    private let deviceSelector: AutoDeviceSelector
    private var deviceMonitorTask: Task<Void, Never>?
    private var iPhoneCameraManager: IPhoneCameraManager?

    init(wearables: WearablesInterface) {
        self.wearables = wearables

        // AutoDeviceSelector automatically picks the best available device.
        // It switches when devices connect/disconnect.
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        // StreamSessionConfig controls video quality from glasses.
        // .low resolution + 24fps is good for AI processing.
        let config = StreamSessionConfig(
            videoCodec: VideoCodec.raw,
            resolution: StreamingResolution.low,
            frameRate: 24
        )
        streamSession = StreamSession(
            streamSessionConfig: config,
            deviceSelector: deviceSelector
        )

        // ── Monitor device availability ──
        deviceMonitorTask = Task { @MainActor in
            for await device in deviceSelector.activeDeviceStream() {
                self.hasActiveDevice = device != nil
            }
        }

        // ── Subscribe to session state changes ──
        // States: .stopped, .waitingForDevice, .starting, .streaming, .paused, .stopping
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateStatusFromState(state)
            }
        }

        // ── Subscribe to video frames ──
        // VideoFrame contains raw camera data. makeUIImage() converts to UIImage.
        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let image = videoFrame.makeUIImage() {
                    self.currentVideoFrame = image
                    if !self.hasReceivedFirstFrame {
                        self.hasReceivedFirstFrame = true
                    }
                    // TODO: Forward to your LLM (throttled to ~1fps)
                    // self.llmSessionVM?.sendVideoFrameIfThrottled(image: image)
                }
            }
        }

        // ── Subscribe to streaming errors ──
        errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newErrorMessage = self.formatStreamingError(error)
                if newErrorMessage != self.errorMessage {
                    self.showError(newErrorMessage)
                }
            }
        }

        updateStatusFromState(streamSession.state)

        // ── Subscribe to photo capture events ──
        photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let uiImage = UIImage(data: photoData.data) {
                    self.capturedPhoto = uiImage
                    self.showPhotoPreview = true
                }
            }
        }
    }

    // MARK: - Start Streaming (with permission request)

    func handleStartStreaming() async {
        let permission = Permission.camera
        do {
            // Step 1: Check if we already have permission
            let status = try await wearables.checkPermissionStatus(permission)
            if status == .granted {
                await startSession()
                return
            }
            // Step 2: Request permission — this opens Meta AI app
            let requestStatus = try await wearables.requestPermission(permission)
            if requestStatus == .granted {
                await startSession()
                return
            }
            showError("Permission denied")
        } catch {
            showError("Permission error: \(error.description)")
        }
    }

    func startSession() async {
        await streamSession.start()
    }

    func stopSession() async {
        if streamingMode == .iPhone {
            stopIPhoneSession()
            return
        }
        await streamSession.stop()
    }

    // MARK: - iPhone Camera Fallback Mode

    func handleStartIPhone() async {
        let granted = await IPhoneCameraManager.requestPermission()
        if granted {
            startIPhoneSession()
        } else {
            showError("Camera permission denied. Please grant access in Settings.")
        }
    }

    private func startIPhoneSession() {
        streamingMode = .iPhone
        let camera = IPhoneCameraManager()
        camera.onFrameCaptured = { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentVideoFrame = image
                if !self.hasReceivedFirstFrame { self.hasReceivedFirstFrame = true }
                // TODO: Forward to your LLM (throttled to ~1fps)
                // self.llmSessionVM?.sendVideoFrameIfThrottled(image: image)
            }
        }
        camera.start()
        iPhoneCameraManager = camera
        streamingStatus = .streaming
    }

    private func stopIPhoneSession() {
        iPhoneCameraManager?.stop()
        iPhoneCameraManager = nil
        currentVideoFrame = nil
        hasReceivedFirstFrame = false
        streamingStatus = .stopped
        streamingMode = .glasses
    }

    // MARK: - Photo Capture (glasses mode only)

    func capturePhoto() {
        streamSession.capturePhoto(format: .jpeg)
    }

    func dismissPhotoPreview() {
        showPhotoPreview = false
        capturedPhoto = nil
    }

    // MARK: - Error Display

    private func showError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }

    // MARK: - State Mapping

    private func updateStatusFromState(_ state: StreamSessionState) {
        switch state {
        case .stopped:
            currentVideoFrame = nil
            streamingStatus = .stopped
        case .waitingForDevice, .starting, .stopping, .paused:
            streamingStatus = .waiting
        case .streaming:
            streamingStatus = .streaming
        }
    }

    // MARK: - Error Formatting

    private func formatStreamingError(_ error: StreamSessionError) -> String {
        switch error {
        case .internalError:
            return "An internal error occurred. Please try again."
        case .deviceNotFound:
            return "Device not found. Please ensure your device is connected."
        case .deviceNotConnected:
            return "Device not connected. Please check your connection and try again."
        case .timeout:
            return "The operation timed out. Please try again."
        case .videoStreamingError:
            return "Video streaming failed. Please try again."
        case .audioStreamingError:
            return "Audio streaming failed. Please try again."
        case .permissionDenied:
            return "Camera permission denied. Please grant permission in Settings."
        case .hingesClosed:
            return "The hinges on the glasses were closed. Please open the hinges and try again."
        @unknown default:
            return "An unknown streaming error occurred."
        }
    }
}
```

---

### A.6 — IPhoneCameraManager (Development Fallback)

> **File**: `GlassesAI/iPhone/IPhoneCameraManager.swift`

```swift
import AVFoundation
import UIKit

class IPhoneCameraManager: NSObject {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "iphone-camera-session")
    private let context = CIContext()
    private var isRunning = false

    var onFrameCaptured: ((UIImage) -> Void)?

    func start() {
        guard !isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
            self?.isRunning = true
        }
    }

    func stop() {
        guard isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            self?.isRunning = false
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            NSLog("[iPhoneCamera] Failed to access back camera")
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Lock rotation to portrait
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        captureSession.commitConfiguration()
    }

    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

extension IPhoneCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)
        onFrameCaptured?(image)
    }
}
```

---

### A.7 — MainAppView (Navigation Hub)

> **File**: `GlassesAI/Views/MainAppView.swift`
> Routes between registration screen and streaming screen based on SDK state.

```swift
import MWDATCore
import SwiftUI

struct MainAppView: View {
    let wearables: WearablesInterface
    @ObservedObject private var viewModel: WearablesViewModel

    init(wearables: WearablesInterface, viewModel: WearablesViewModel) {
        self.wearables = wearables
        self.viewModel = viewModel
    }

    var body: some View {
        if viewModel.registrationState == .registered || viewModel.hasMockDevice {
            // User is registered — show the streaming interface
            StreamSessionView(wearables: wearables, wearablesVM: viewModel)
        } else {
            // Not registered — show onboarding with "Connect my glasses" button
            HomeScreenView(viewModel: viewModel)
        }
    }
}
```

---

### A.8 — HomeScreenView (Registration / Onboarding)

> **File**: `GlassesAI/Views/HomeScreenView.swift`

```swift
import MWDATCore
import SwiftUI

struct HomeScreenView: View {
    @ObservedObject var viewModel: WearablesViewModel

    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)

            VStack(spacing: 12) {
                Spacer()

                // TODO: Replace with your app logo
                Image(systemName: "eyeglasses")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80)
                    .foregroundColor(.blue)

                Text("GlassesAI")
                    .font(.system(size: 28, weight: .bold))

                Text("Connect your Meta Ray-Ban glasses to get started with your AI assistant.")
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 20) {
                    Text("You'll be redirected to the Meta AI app to confirm your connection.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Button(action: {
                        viewModel.connectGlasses()
                    }) {
                        Text(viewModel.registrationState == .registering
                             ? "Connecting..." : "Connect my glasses")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .cornerRadius(30)
                    }
                    .disabled(viewModel.registrationState == .registering)
                    .opacity(viewModel.registrationState == .registering ? 0.6 : 1.0)
                }
            }
            .padding(.all, 24)
        }
    }
}
```

---

### A.9 — StreamSessionView (Streaming Container)

> **File**: `GlassesAI/Views/StreamSessionView.swift`
> Switches between the active streaming UI and the pre-streaming setup view.

```swift
import MWDATCore
import SwiftUI

struct StreamSessionView: View {
    let wearables: WearablesInterface
    @ObservedObject private var wearablesViewModel: WearablesViewModel
    @StateObject private var viewModel: StreamSessionViewModel
    // TODO: Add your LLM session view model here
    // @StateObject private var llmVM = LLMSessionViewModel()

    init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
        self.wearables = wearables
        self.wearablesViewModel = wearablesVM
        self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
    }

    var body: some View {
        ZStack {
            if viewModel.isStreaming {
                // Active streaming — show video feed + controls
                StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel)
            } else {
                // Pre-streaming — show start buttons
                NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // TODO: Wire LLM view model
            // viewModel.llmSessionVM = llmVM
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
```

---

### A.10 — NonStreamView (Pre-Streaming Setup)

> **File**: `GlassesAI/Views/NonStreamView.swift`
> Shows "Start streaming" and "Start on iPhone" buttons.

```swift
import MWDATCore
import SwiftUI

struct NonStreamView: View {
    @ObservedObject var viewModel: StreamSessionViewModel
    @ObservedObject var wearablesVM: WearablesViewModel

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                HStack {
                    Spacer()
                    Menu {
                        Button("Disconnect", role: .destructive) {
                            wearablesVM.disconnectGlasses()
                        }
                        .disabled(wearablesVM.registrationState != .registered)
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(width: 60)

                    Text("Stream Your Glasses Camera")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Tap Start streaming to begin, or use iPhone mode for development without glasses.")
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                // Device waiting indicator
                if !viewModel.hasActiveDevice {
                    HStack(spacing: 8) {
                        Image(systemName: "hourglass")
                            .foregroundColor(.white.opacity(0.7))
                        Text("Waiting for an active device")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 12)
                }

                // iPhone fallback button
                Button(action: {
                    Task { await viewModel.handleStartIPhone() }
                }) {
                    Text("Start on iPhone")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color(white: 0.25))
                        .cornerRadius(30)
                }

                // Glasses streaming button
                Button(action: {
                    Task { await viewModel.handleStartStreaming() }
                }) {
                    Text("Start streaming")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(viewModel.hasActiveDevice ? Color.blue : Color.gray)
                        .cornerRadius(30)
                }
                .disabled(!viewModel.hasActiveDevice)
            }
            .padding(.all, 24)
        }
    }
}
```

---

### A.11 — StreamView (Active Streaming UI)

> **File**: `GlassesAI/Views/StreamView.swift`
> Full-screen video feed with controls overlay. Wire your LLM overlay here.

```swift
import MWDATCore
import SwiftUI

struct StreamView: View {
    @ObservedObject var viewModel: StreamSessionViewModel
    @ObservedObject var wearablesVM: WearablesViewModel
    // TODO: Add your LLM view model
    // @ObservedObject var llmVM: LLMSessionViewModel

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            // Video feed — full screen
            if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
                GeometryReader { geometry in
                    Image(uiImage: videoFrame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .edgesIgnoringSafeArea(.all)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .foregroundColor(.white)
            }

            // TODO: Add LLM status overlay here (status pills, transcripts, speaking indicator)

            // Bottom controls
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    // Stop streaming
                    Button(action: {
                        Task { await viewModel.stopSession() }
                    }) {
                        Text("Stop streaming")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(30)
                    }

                    // Photo capture (glasses only — DAT SDK feature)
                    if viewModel.streamingMode == .glasses {
                        Button(action: { viewModel.capturePhoto() }) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(.white)
                                .clipShape(Circle())
                        }
                    }

                    // TODO: Add AI toggle button here
                    // Button for starting/stopping LLM session
                }
            }
            .padding(.all, 24)
        }
        .onDisappear {
            Task {
                if viewModel.streamingStatus != .stopped {
                    await viewModel.stopSession()
                }
            }
        }
        .sheet(isPresented: $viewModel.showPhotoPreview) {
            if let photo = viewModel.capturedPhoto {
                // Simple photo preview — replace with your own UI
                VStack {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                    Button("Dismiss") { viewModel.dismissPhotoPreview() }
                        .padding()
                }
            }
        }
    }
}
```

---

### A.12 — AudioManager (Complete Bidirectional Audio)

> **File**: `GlassesAI/LLM/AudioManager.swift`
> Handles mic capture (PCM 16kHz Int16 mono) and speaker playback (PCM 24kHz Int16 mono).
> This is the **exact** audio engine from the reference codebase — battle-tested with resampling, accumulation, and format conversion.

```swift
import AVFoundation
import Foundation

class AudioManager {
    var onAudioCaptured: ((Data) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isCapturing = false

    private let outputFormat: AVAudioFormat

    private let sendQueue = DispatchQueue(label: "audio.accumulator")
    private var accumulatedData = Data()
    private let minSendBytes = 3200  // 100ms at 16kHz mono Int16 = 1600 frames * 2 bytes

    // TODO: CHANGE THESE if your LLM uses different sample rates
    private let inputSampleRate: Double = 16000   // Mic → LLM
    private let outputSampleRate: Double = 24000   // LLM → Speaker
    private let channels: UInt32 = 1
    private let bitsPerSample: UInt32 = 16

    init() {
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: outputSampleRate,
            channels: channels,
            interleaved: true
        )!
    }

    func setupAudioSession(useIPhoneMode: Bool = false) throws {
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat
        try session.setCategory(
            .playAndRecord, mode: mode,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try session.setPreferredSampleRate(inputSampleRate)
        try session.setPreferredIOBufferDuration(0.064)
        try session.setActive(true)
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        audioEngine.attach(playerNode)
        let playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: channels,
            interleaved: false
        )!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

        let inputNode = audioEngine.inputNode
        let inputNativeFormat = inputNode.outputFormat(forBus: 0)

        let needsResample = inputNativeFormat.sampleRate != inputSampleRate
            || inputNativeFormat.channelCount != channels

        sendQueue.async { self.accumulatedData = Data() }

        var converter: AVAudioConverter?
        if needsResample {
            let resampleFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputSampleRate,
                channels: channels,
                interleaved: false
            )!
            converter = AVAudioConverter(from: inputNativeFormat, to: resampleFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNativeFormat) {
            [weak self] buffer, _ in
            guard let self else { return }

            let pcmData: Data
            if let converter {
                let resampleFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: self.inputSampleRate,
                    channels: self.channels,
                    interleaved: false
                )!
                guard let resampled = self.convertBuffer(buffer, using: converter,
                                                          targetFormat: resampleFormat) else { return }
                pcmData = self.float32BufferToInt16Data(resampled)
            } else {
                pcmData = self.float32BufferToInt16Data(buffer)
            }

            self.sendQueue.async {
                self.accumulatedData.append(pcmData)
                if self.accumulatedData.count >= self.minSendBytes {
                    let chunk = self.accumulatedData
                    self.accumulatedData = Data()
                    self.onAudioCaptured?(chunk)
                }
            }
        }

        try audioEngine.start()
        playerNode.play()
        isCapturing = true
    }

    func playAudio(data: Data) {
        guard isCapturing, !data.isEmpty else { return }

        let playerFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputSampleRate,
            channels: channels,
            interleaved: false
        )!

        let frameCount = UInt32(data.count) / (bitsPerSample / 8 * channels)
        guard frameCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        guard let floatData = buffer.floatChannelData else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<Int(frameCount) {
                floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying { playerNode.play() }
    }

    func stopPlayback() {
        playerNode.stop()
        playerNode.play()
    }

    func stopCapture() {
        guard isCapturing else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        audioEngine.detach(playerNode)
        isCapturing = false
        sendQueue.async {
            if !self.accumulatedData.isEmpty {
                let chunk = self.accumulatedData
                self.accumulatedData = Data()
                self.onAudioCaptured?(chunk)
            }
        }
    }

    // MARK: - Private helpers

    private func float32BufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let floatData = buffer.floatChannelData else { return Data() }
        var int16Array = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, floatData[0][i]))
            int16Array[i] = Int16(sample * Float(Int16.max))
        }
        return int16Array.withUnsafeBufferPointer { ptr in Data(buffer: ptr) }
    }

    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCount = UInt32(Double(inputBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                    frameCapacity: outputFrameCount) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if error != nil { return nil }
        return outputBuffer
    }
}
```

---

### A.13 — Mock Device Support (DEBUG Only)

> **File**: `GlassesAI/ViewModels/MockDeviceKit/MockDeviceKitViewModel.swift`
> For testing streaming without physical glasses.

```swift
#if DEBUG

import Foundation
import MWDATMockDevice

// View model for the mock device management sheet
@MainActor
class MockDeviceKitViewModel: ObservableObject {
    private let mockDeviceKit: MockDeviceKitInterface
    @Published var devices: [MockDevice] = []

    init(mockDeviceKit: MockDeviceKitInterface) {
        self.mockDeviceKit = mockDeviceKit
        self.devices = mockDeviceKit.pairedDevices
    }

    func pairRaybanMeta() {
        let device = mockDeviceKit.pairRaybanMeta()
        devices.append(device)
    }

    func unpairDevice(_ device: MockDevice) {
        mockDeviceKit.unpairDevice(device)
        devices.removeAll { $0.deviceIdentifier == device.deviceIdentifier }
    }

    /// Quick setup: pair, power on, unfold — ready to stream
    func pairAndActivate() {
        let device = mockDeviceKit.pairRaybanMeta()
        device.powerOn()
        if let glasses = device as? MockDisplaylessGlasses {
            glasses.unfold()
        }
        devices.append(device)
    }

    /// Load a mock video feed for testing
    func loadVideoFeed(_ device: MockDevice, from url: URL) async {
        if let cameraKit = (device as? MockDisplaylessGlasses)?.getCameraKit() {
            await cameraKit.setCameraFeed(fileURL: url)
        }
    }

    /// Load a mock captured image for testing photo capture
    func loadCapturedImage(_ device: MockDevice, from url: URL) async {
        if let cameraKit = (device as? MockDisplaylessGlasses)?.getCameraKit() {
            await cameraKit.setCapturedImage(fileURL: url)
        }
    }
}

@MainActor
class DebugMenuViewModel: ObservableObject {
    @Published var showDebugMenu: Bool = false
    @Published var mockDeviceKitViewModel: MockDeviceKitViewModel

    init(mockDeviceKit: MockDeviceKitInterface) {
        self.mockDeviceKitViewModel = MockDeviceKitViewModel(mockDeviceKit: mockDeviceKit)
    }
}

#endif
```

> **File**: `GlassesAI/Views/DebugMenuView.swift`

```swift
#if DEBUG

import SwiftUI

struct DebugMenuView: View {
    @ObservedObject var debugMenuViewModel: DebugMenuViewModel

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                Button(action: { debugMenuViewModel.showDebugMenu = true }) {
                    Image(systemName: "ladybug.fill")
                        .foregroundColor(.white)
                        .padding()
                        .background(.secondary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                Spacer()
            }
            .padding(.trailing)
        }
    }
}

struct MockDeviceKitView: View {
    @ObservedObject var viewModel: MockDeviceKitViewModel

    var body: some View {
        NavigationView {
            List {
                Section("Mock Devices (\(viewModel.devices.count))") {
                    ForEach(viewModel.devices, id: \.deviceIdentifier) { device in
                        HStack {
                            Text(device.deviceIdentifier)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button("Unpair", role: .destructive) {
                                viewModel.unpairDevice(device)
                            }
                        }
                    }
                }
                Section("Actions") {
                    Button("Pair + Activate Ray-Ban Meta") {
                        viewModel.pairAndActivate()
                    }
                }
            }
            .navigationTitle("Mock Device Kit")
        }
    }
}

#endif
```

---

### A.14 — Integration Test (Verify Streaming Works)

> **File**: `GlassesAITests/IntegrationTests.swift`
> Copy this to verify your DAT SDK wiring is correct.

```swift
import Foundation
import MWDATCore
import MWDATMockDevice
import SwiftUI
import XCTest

@testable import GlassesAI  // TODO: CHANGE THIS to your target name

@MainActor
class ViewModelIntegrationTests: XCTestCase {

    private var mockDevice: MockRaybanMeta?
    private var cameraKit: MockCameraKit?

    override func setUp() async throws {
        try await super.setUp()
        try? Wearables.configure()

        let pairedMockDevice = MockDeviceKit.shared.pairRaybanMeta()
        mockDevice = pairedMockDevice
        cameraKit = pairedMockDevice.getCameraKit()

        pairedMockDevice.powerOn()
        pairedMockDevice.unfold()

        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    override func tearDown() async throws {
        MockDeviceKit.shared.pairedDevices.forEach { mockDevice in
            MockDeviceKit.shared.unpairDevice(mockDevice)
        }
        mockDevice = nil
        cameraKit = nil
        try await super.tearDown()
    }

    func testVideoStreamingFlow() async throws {
        guard let camera = cameraKit else {
            XCTFail("Mock device and camera should be available")
            return
        }

        // Load a test video — add a "plant.mp4" to your test bundle
        guard let videoURL = Bundle(for: type(of: self)).url(forResource: "plant", withExtension: "mp4") else {
            XCTFail("Could not find test video resource")
            return
        }

        await camera.setCameraFeed(fileURL: videoURL)

        let viewModel = StreamSessionViewModel(wearables: Wearables.shared)

        XCTAssertEqual(viewModel.streamingStatus, .stopped)
        XCTAssertFalse(viewModel.isStreaming)
        XCTAssertNil(viewModel.currentVideoFrame)

        await viewModel.handleStartStreaming()
        try await Task.sleep(nanoseconds: 10_000_000_000)  // Wait 10s for frames

        XCTAssertTrue(viewModel.isStreaming)
        XCTAssertTrue(viewModel.hasReceivedFirstFrame)
        XCTAssertNotNil(viewModel.currentVideoFrame)

        await viewModel.stopSession()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        XCTAssertFalse(viewModel.isStreaming)
    }
}
```

---

### A.15 — SPM Package Reference (for `project.pbxproj`)

If you're wiring the package dependency manually, here's the exact reference:

```
/* XCRemoteSwiftPackageReference */
repositoryURL = "https://github.com/facebook/meta-wearables-dat-ios"
requirement = {
    kind = exactVersion;
    version = 0.4.0;
}

/* Products to add to your target: */
MWDATCore
MWDATCamera
MWDATMockDevice  (link to DEBUG target only)
```

---

### A.16 — Quick Reference: DAT SDK API Cheat Sheet

```
┌─────────────────────────────────────────────────────────────────────┐
│                     META DAT SDK CHEAT SHEET                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  INIT (once at launch)                                              │
│    try Wearables.configure()                                        │
│    let sdk = Wearables.shared                                       │
│                                                                     │
│  REGISTRATION                                                       │
│    try await sdk.startRegistration()    // Opens Meta AI app        │
│    try await sdk.handleUrl(url)         // Process callback         │
│    try await sdk.startUnregistration()  // Disconnect               │
│    sdk.registrationState                // .registered/ing/unregistered │
│    sdk.registrationStateStream()        // AsyncSequence             │
│                                                                     │
│  DEVICES                                                            │
│    sdk.devices                          // [DeviceIdentifier]       │
│    sdk.devicesStream()                  // AsyncSequence             │
│    sdk.deviceForIdentifier(id)          // Device?                  │
│    device.compatibility()               // .compatible / .updateRequired │
│    device.addCompatibilityListener { }  // → AnyListenerToken      │
│    device.nameOrId()                    // String                   │
│                                                                     │
│  PERMISSIONS                                                        │
│    try await sdk.checkPermissionStatus(.camera) // .granted/.denied │
│    try await sdk.requestPermission(.camera)     // Opens Meta AI    │
│                                                                     │
│  STREAMING                                                          │
│    let selector = AutoDeviceSelector(wearables: sdk)                │
│    let config = StreamSessionConfig(                                │
│        videoCodec: .raw,                                            │
│        resolution: .low,   // .low / .medium / .high                │
│        frameRate: 24                                                │
│    )                                                                │
│    let session = StreamSession(                                     │
│        streamSessionConfig: config,                                 │
│        deviceSelector: selector                                     │
│    )                                                                │
│                                                                     │
│    session.statePublisher.listen { state in }                       │
│      // .stopped .waitingForDevice .starting .streaming             │
│      // .paused .stopping                                           │
│                                                                     │
│    session.videoFramePublisher.listen { frame in                    │
│      let image = frame.makeUIImage()    // UIImage?                 │
│    }                                                                │
│                                                                     │
│    session.errorPublisher.listen { error in }                       │
│      // .internalError .deviceNotFound .deviceNotConnected          │
│      // .timeout .videoStreamingError .audioStreamingError          │
│      // .permissionDenied .hingesClosed                             │
│                                                                     │
│    await session.start()                                            │
│    await session.stop()                                             │
│                                                                     │
│  PHOTO CAPTURE                                                      │
│    session.capturePhoto(format: .jpeg)  // or .heic                 │
│    session.photoDataPublisher.listen { photoData in                 │
│      let image = UIImage(data: photoData.data)                      │
│    }                                                                │
│                                                                     │
│  DEVICE SELECTOR                                                    │
│    selector.activeDeviceStream()        // AsyncSequence<Device?>   │
│                                                                     │
│  MOCK DEVICES (DEBUG only)                                          │
│    import MWDATMockDevice                                           │
│    let mock = MockDeviceKit.shared.pairRaybanMeta()                 │
│    mock.powerOn()                                                   │
│    mock.unfold()           // MockDisplaylessGlasses                │
│    mock.getCameraKit()     // MockCameraKit                         │
│    cameraKit.setCameraFeed(fileURL: url)       // async             │
│    cameraKit.setCapturedImage(fileURL: url)    // async             │
│    MockDeviceKit.shared.unpairDevice(mock)                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Summary of Execution Steps

1. **Create Xcode project** with SwiftUI, iOS 17 target
2. **Add DAT SDK** via SPM (MWDATCore, MWDATCamera, MWDATMockDevice)
3. **Copy `Info.plist`** from Appendix A.1 — all DAT keys, permissions, URL scheme, background modes
4. **Copy `GlassesAIApp.swift`** from A.2 — SDK init, wiring
5. **Copy `WearablesViewModel.swift`** from A.3 — registration, device discovery, compatibility
6. **Copy `RegistrationView.swift`** from A.4 — URL callback handler (must be in view hierarchy)
7. **Copy `StreamSessionViewModel.swift`** from A.5 — streaming lifecycle, permissions, video frames, photos, errors
8. **Copy `IPhoneCameraManager.swift`** from A.6 — development fallback
9. **Copy the Views** from A.7–A.11 — MainAppView, HomeScreen, StreamSession, NonStream, Stream
10. **Copy `AudioManager.swift`** from A.12 — bidirectional audio for LLM
11. **Copy mock device code** from A.13 — DEBUG testing support
12. **Integrate your chosen LLM** using Section 8 (Claude/GPT-4o/Grok)
13. **Wire video frames** from StreamSessionViewModel → LLM (throttled to ~1fps, JPEG 50%, base64)
14. **Wire audio** from AudioManager → LLM and LLM → AudioManager
15. **Run integration test** from A.14 to verify the pipeline
16. **Ship it**
