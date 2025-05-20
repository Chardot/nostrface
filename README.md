# NostrFace

NostrFace is a Flutter application that allows users to discover interesting profiles in the Nostr network using a Tinder-like swiping interface.

## Features

- Swipeable card interface for discovering Nostr profiles
- View detailed profile information and recent posts
- Connect with your Nostr private key
- Generate new Nostr keys
- Read-only mode for browsing without authentication
- Dark/light theme support

## Project Structure

The project follows a feature-based architecture with the following structure:

```
lib/
├── core/                    # Core functionality
│   ├── config/              # App-wide configuration
│   ├── models/              # Data models
│   ├── services/            # Services for API interaction
│   └── utils/               # Utility functions
├── features/                # App features
│   ├── auth/                # Authentication
│   ├── profile_discovery/   # Profile discovery (swiping)
│   ├── profile_view/        # Profile details view
│   └── settings/            # App settings
└── shared/                  # Shared components
    ├── constants/           # App-wide constants
    ├── providers/           # Shared providers
    └── widgets/             # Reusable widgets
```

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Android Studio / VS Code with Flutter extensions
- An iOS device or simulator (for iOS testing)
- An Android device or emulator (for Android testing)

### Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/nostrface.git
   ```

2. Navigate to the project directory:
   ```
   cd nostrface
   ```

3. Install dependencies:
   ```
   flutter pub get
   ```

4. Run the code generators:
   ```
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

5. Run the app:
   ```
   flutter run
   ```

## Nostr Integration

NostrFace integrates with the Nostr protocol by:

1. Connecting to multiple Nostr relays to fetch profile data
2. Supporting NIP-01 for basic event types
3. Supporting NIP-02 for contact lists
4. Supporting NIP-05 for verified identities

## Development Roadmap

- [x] Basic app structure and UI
- [x] Profile discovery interface
- [x] Profile detail view
- [x] Settings screen
- [x] Authentication service
- [ ] Enhanced profile recommendations
- [ ] Implement follow functionality
- [ ] Implement direct messaging
- [ ] Offline support
- [ ] Content filters
- [ ] Custom relay management

## Deployment

For detailed deployment instructions, see [docs/deployment.md](docs/nostrface_plan.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- The Nostr protocol developers
- The Flutter team for the amazing framework
- All the contributors to the open-source libraries used in this project