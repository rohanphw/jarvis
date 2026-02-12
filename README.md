# Jarvis - AI Assistant for Meta Ray-Ban Smart Glasses

> Real-time vision + voice AI powered by Claude, streaming at 30 FPS from your Meta Ray-Ban glasses

[![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Jarvis transforms your Meta Ray-Ban smart glasses into an intelligent AI companion. Stream what you see in real-time, have natural voice conversations with Claude, and get instant insights about your surroundings - all with the elegance of J.A.R.V.I.S. from Iron Man.

## ✨ Features

- 🎥 **30 FPS Video Streaming** - Real-time video from Meta Ray-Ban glasses via Bluetooth
- 🎤 **Natural Voice Conversations** - Talk to Claude AI with sophisticated female voice synthesis
- 👁️ **Real-time Vision** - Claude sees what you see and responds contextually
- 📸 **Photo Capture** - Take high-res photos with AI-generated descriptions
- 💾 **Conversation History** - Full searchable history with visual snapshots
- 🔐 **Secure API Key Storage** - In-app key management with iOS Keychain
- 🎨 **Glassmorphism UI** - Minimal, elegant design with Apple-like aesthetics
- 📱 **iPhone Fallback Mode** - Test without glasses using iPhone camera
- 🌐 **100+ Languages** - Voice support for multiple languages
- 🔍 **Smart Search** - Find past conversations instantly

## 🎬 Demo

> **Note:** Add screenshots/videos here once available

## 📋 Prerequisites

Before you begin, ensure you have:

- **Development Environment:**
  - macOS Monterey (12.0) or later
  - Xcode 15.0 or later
  - iOS device running iOS 17.0+ (not simulator - requires Bluetooth)

- **Hardware:**
  - Meta Ray-Ban smart glasses (Wayfarer or other models)
  - OR use iPhone camera for testing (fallback mode)

- **Accounts & API Keys:**
  - [Anthropic API key](https://console.anthropic.com/) (Claude)
  - Meta AI app installed on your iPhone
  - Developer Mode enabled in Meta AI app (free)

## 🚀 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/jarvis.git
cd jarvis
```

### 2. Install Dependencies

This project uses Swift Package Manager. Dependencies will be resolved automatically when you open the project in Xcode.

Required packages:
- [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios) (v0.4.0)

### 3. Open in Xcode

```bash
open Jarvis/Jarvis.xcodeproj
```

### 4. Configure Constants

The project includes a template configuration file:

```bash
# The Constants.swift file is gitignored and will be empty by default
# This is intentional - API keys are managed in-app!
```

**Note:** You do NOT need to add your API key to any config file. The app handles API key management securely through its Settings interface.

### 5. Configure Code Signing

1. In Xcode, select the **Jarvis** target
2. Go to **Signing & Capabilities**
3. Select your **Development Team**
4. Xcode will automatically manage provisioning profiles

### 6. Build and Run

1. Connect your iPhone via USB
2. Select your device in Xcode
3. Press **Cmd+R** to build and run

## ⚙️ Configuration

### First Launch Setup

When you first launch Jarvis, you'll be guided through a setup process:

#### 1. API Key Setup
- The app will show an "API Key Required" screen
- Tap **Setup**
- Enter your Anthropic API key (starts with `sk-ant-`)
- Get your key from: [console.anthropic.com](https://console.anthropic.com/)
- The key is stored securely in iOS Keychain

#### 2. Meta Glasses Connection (Developer Mode)

**Enable Developer Mode:**
1. Install the **Meta AI** app from the App Store
2. Pair your Meta Ray-Ban glasses with the Meta AI app
3. In Meta AI app: **Settings → Devices → [Your Glasses] → Developer Mode**
4. Enable **Developer Mode** (free, no registration required)

**Connect Glasses to Jarvis:**
1. Open Jarvis app
2. Ensure Bluetooth is enabled on iPhone
3. Tap **Start Session** when glasses are detected
4. Grant camera and microphone permissions when prompted

#### 3. Permissions

Jarvis requires the following permissions:
- **Bluetooth** - To connect to Meta Ray-Ban glasses
- **Microphone** - For voice conversations with Claude
- **Camera** - For iPhone fallback mode (optional)
- **Photos** - To save captured photos (optional)

### Advanced Configuration

#### Custom Settings

Edit `Jarvis/Jarvis/Config/Constants.swift` for advanced options:

```swift
// Video quality (adjust for performance)
enum Video {
    static let streamingFPS: Int = 30        // Max from glasses
    static let llmThrottleFPS: Double = 1.5  // Sent to Claude
    static let jpegQuality: CGFloat = 0.5    // Compression (0.0-1.0)
}

// Feature flags
enum Features {
    static let enableIPhoneFallback: Bool = true
    static let enablePhotoCapture: Bool = true
}
```

#### Managing API Keys

**View/Change API Key:**
1. Open Jarvis
2. Tap **API Key** tile on home screen
3. Update or delete your key

**Delete API Key:**
1. Tap **API Key** tile
2. Tap **Delete API Key**
3. Confirm deletion

## 📱 Usage

### Starting a Session

1. **Launch Jarvis** and ensure status shows "Ready" (green dot)
2. Tap **Start Session**
3. Video stream appears at top, conversation area at bottom
4. **Just start talking** - Claude will respond naturally

### During a Session

- **Talk naturally** - Claude sees what you're looking at and responds contextually
- **Capture photos** - Tap camera icon (glasses mode only)
- **View transcript** - Real-time text appears at bottom
- **End session** - Tap "End Session" button

### Conversation History

- **View past conversations** - Tap **History** tile on home screen
- **Search** - Use search bar to find specific conversations
- **View details** - Tap any conversation to see full transcript with snapshots
- **Export** - Share conversations as text
- **Delete** - Swipe left on any conversation

### Voice Settings

Customize Claude's voice:
- Navigate to **Settings → Voice**
- Adjust speech rate, voice selection (coming soon)
- Change language preferences

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│          User Interface Layer           │
│  (SwiftUI Views + MVVM ViewModels)     │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│         Service Layer                   │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Wearables    │  │ Claude Vision   │ │
│  │ Service      │  │ Service         │ │
│  │ (DAT SDK)    │  │ (Anthropic API) │ │
│  └──────────────┘  └─────────────────┘ │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Streaming    │  │ Speech          │ │
│  │ Service      │  │ Services        │ │
│  └──────────────┘  └─────────────────┘ │
└────────────┬────────────────────────────┘
             │
┌────────────▼────────────────────────────┐
│       Persistence Layer                 │
│  (SwiftData + Keychain)                │
└─────────────────────────────────────────┘
```

### Key Components

- **WearablesService** - Manages Meta glasses connection and device discovery
- **StreamingService** - Handles 30 FPS video streaming with frame throttling
- **ClaudeVisionService** - Communicates with Claude API (vision + text)
- **TextToSpeechManager** - Natural voice synthesis with premium voices
- **SpeechRecognitionManager** - Real-time speech-to-text
- **ConversationRepository** - SwiftData persistence with search
- **KeychainManager** - Secure API key storage

## 🔧 Troubleshooting

### Common Issues

#### "Device Disconnected" Status

**Causes:**
- Glasses are powered off
- Glasses hinges are closed (they auto-sleep)
- Bluetooth disabled on iPhone
- Glasses not in Developer Mode

**Solutions:**
1. Open glasses hinges fully
2. Check Bluetooth is enabled
3. Verify Developer Mode in Meta AI app
4. Try unpairing and re-pairing in Meta AI app

#### "API Key Required" Status

**Solution:**
1. Tap **API Key** tile
2. Enter your Anthropic API key
3. Get key from [console.anthropic.com](https://console.anthropic.com/)

#### Video Stream Laggy

**Solutions:**
1. Close other Bluetooth-heavy apps
2. Reduce `Video.jpegQuality` in Constants.swift
3. Lower `Video.llmThrottleFPS` if needed
4. Ensure strong Bluetooth connection (keep glasses close to phone)

#### No Audio Response

**Causes:**
- Invalid API key
- Microphone permission denied
- Speaker volume too low

**Solutions:**
1. Verify API key in Settings
2. Check microphone permission: **Settings → Jarvis → Microphone**
3. Increase volume
4. Try toggling between glasses/iPhone audio modes

#### App Crashes on Launch

**Solutions:**
1. Clean build folder: **Cmd+Shift+K**
2. Delete derived data: **Xcode → Preferences → Locations → Derived Data**
3. Reinstall app on device
4. Check Console app for crash logs

### Performance Optimization

If experiencing lag or high battery drain:

```swift
// In Constants.swift, reduce these values:
enum Video {
    static let llmThrottleFPS: Double = 1.0  // From 1.5
    static let jpegQuality: CGFloat = 0.3    // From 0.5
}
```

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Push to the branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Development Guidelines

- Follow Swift style guide and conventions
- Add comments for complex logic
- Test on real device before submitting PR
- Update README if adding new features
- Keep commits atomic and well-described

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Meta** - For the [Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios)
- **Anthropic** - For the Claude API powering the AI capabilities
- **Apple** - For the excellent SwiftUI and iOS frameworks
- **Marvel Studios** - For the inspiration (J.A.R.V.I.S. from Iron Man)

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/yourusername/jarvis/issues)
- **Discussions:** [GitHub Discussions](https://github.com/yourusername/jarvis/discussions)
- **Meta Wearables Docs:** [developers.meta.com/wearables](https://developers.meta.com/wearables)
- **Claude API Docs:** [docs.anthropic.com](https://docs.anthropic.com)

## 🗺️ Roadmap

- [ ] Real-time web search integration
- [ ] Custom wake word detection
- [ ] Multi-language UI
- [ ] Apple Watch companion app
- [ ] Siri Shortcuts integration
- [ ] iCloud sync for conversation history
- [ ] Custom voice selection
- [ ] Gesture controls from glasses

## 💰 Cost Estimation

**Claude API Pricing:**
- Vision API: ~$0.003 per image (1-2 FPS = $0.18-$0.36 per 10-min session)
- Text generation: ~$0.003 per 1K tokens
- **Estimated:** $0.50-$1.00 per hour of active use

**Tips to reduce costs:**
- Lower `llmThrottleFPS` to send fewer images
- Use shorter sessions
- Monitor usage in [Anthropic Console](https://console.anthropic.com/)

## ⚠️ Important Notes

- **Privacy:** All conversations are stored locally on your device. Enable iCloud sync cautiously.
- **Battery:** Continuous video streaming drains battery faster. Consider bringing a portable charger.
- **Data Usage:** Streaming video to Claude uses data. Use Wi-Fi when possible or monitor cellular usage.
- **Developer Mode:** Meta's Developer Mode is free but may have usage limits. Check Meta's documentation.

## 📸 Gallery

> - Home screen
> - Streaming session in action
> - Conversation history
> - API key setup
> - Settings panel
