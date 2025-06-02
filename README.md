# NostrFace

A Tinder-like profile discovery app for the Nostr protocol, built with Flutter. Swipe through profiles, follow interesting people, and connect with the decentralized social network.

![Flutter](https://img.shields.io/badge/Flutter-3.32+-blue.svg)
![Dart](https://img.shields.io/badge/Dart-3.8+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

### 🔍 Profile Discovery
- **Swipeable Interface**: Browse profiles with an intuitive card-swiping interface
- **Smart Buffering**: Pre-fetches profiles for seamless browsing
- **Quality Filtering**: Only shows profiles with valid images and content
- **Pull to Refresh**: Easily refresh the profile feed

### 🔐 Authentication
- **Flexible Login**: Support for both nsec and hex private keys
- **Key Generation**: Create new Nostr identities in-app
- **Secure Storage**: Keys are encrypted and stored securely
- **Guest Mode**: Browse profiles without logging in

### 👥 Social Features
- **Follow/Unfollow**: Build your network with instant UI feedback
- **Profile Views**: See detailed profiles with bio, website, and verification status
- **Recent Posts**: View formatted notes with rich content support
- **Direct Messaging**: Send encrypted messages using NIP-44 standard

### 💬 Rich Content
- **@Mentions**: Properly formatted and clickable user mentions
- **Media Display**: Inline images with full-screen viewer
- **Link Detection**: Automatic URL formatting and click handling
- **Share Notes**: Share posts via system share sheet or copy links

### ⚙️ Settings & Management
- **Relay Management**: Configure and manage Nostr relay connections
- **Discarded Profiles**: Track and restore profiles you've passed on
- **Dark Mode**: Toggle between light and dark themes
- **Profile Management**: View your public key and manage authentication

## Installation

### Prerequisites

- Flutter SDK (3.32.0 or higher)
- Dart SDK (3.8.0 or higher)
- iOS: Xcode 14+ and iOS 12+
- Android: Android Studio and SDK 21+
- Web: Chrome or any modern browser

### Setup Instructions

1. **Clone the repository**
   ```bash
   git clone https://github.com/Chardot/nostrface.git
   cd nostrface
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   
   For iOS:
   ```bash
   flutter run -d ios
   ```
   
   For Android:
   ```bash
   flutter run -d android
   ```
   
   For Web:
   ```bash
   flutter run -d chrome
   ```

### Build for Production

1. **iOS**
   ```bash
   flutter build ios --release
   ```
   Then open `ios/Runner.xcworkspace` in Xcode to archive and distribute.

2. **Android**
   ```bash
   flutter build apk --release
   # or for app bundle:
   flutter build appbundle --release
   ```

3. **Web**
   ```bash
   flutter build web --release
   ```
   The build output will be in `build/web/`

## Development

### Project Structure

```
nostrface/
├── lib/
│   ├── main.dart              # App entry point
│   ├── core/                  # Core functionality
│   │   ├── models/           # Data models
│   │   ├── services/         # Business logic
│   │   ├── providers/        # State management
│   │   └── utils/           # Utilities
│   ├── features/             # Feature modules
│   │   ├── auth/            # Authentication
│   │   ├── profile_discovery/# Main swipe interface
│   │   ├── profile_view/    # Profile details
│   │   ├── direct_messages/ # Messaging
│   │   └── settings/        # App settings
│   └── shared/              # Shared widgets
├── test/                    # Unit tests
└── integration_test/        # Integration tests
```

### Key Technologies

- **State Management**: Riverpod
- **Navigation**: GoRouter
- **Local Storage**: Hive & Flutter Secure Storage
- **Networking**: WebSocket for Nostr relays
- **UI Components**: Material Design 3
- **Image Loading**: CachedNetworkImage

### Running Tests

```bash
# Run unit tests
flutter test

# Run with coverage
flutter test --coverage
```

## Nostr Protocol Implementation

NostrFace implements several Nostr Improvement Proposals (NIPs):

- **NIP-01**: Basic protocol and event format
- **NIP-04**: Encrypted Direct Messages (legacy support)
- **NIP-44**: Modern encrypted messaging
- **NIP-05**: DNS-based verification
- **NIP-19**: Bech32-encoded entities (npub, nsec, note, nprofile)

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built for the Nostr community
- Inspired by Tinder's UX for social discovery
- Uses the [nostr](https://pub.dev/packages/nostr) Dart package

## Contact

For questions or support, please open an issue on GitHub.

---

**Note**: This app requires connection to Nostr relays. The default relay is `wss://relay.nos.social`, but you can configure additional relays in the settings.