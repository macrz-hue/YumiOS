# Yumehiru Kotlin App

## Quick Start (No Build Needed)
```bash
yumehiru dashboard   # Show dashboard overview
yumehiru status      # System health
yumehiru tasks       # List tasks
yumehiru alerts      # Show alerts
yumehiru speak       # Speak current status via TTS
yumehiru watch       # Live alert monitoring with voice
```

## Building for Desktop
Requires: JDK 17+, 4GB+ RAM, Gradle 8.5
```bash
./gradlew run                    # Run the Compose Desktop app
./gradlew packageDeb             # Build .deb package
```

## Project Structure
```
kotlin-app/
├── yumehiru                    # Shell CLI (works now)
├── build.gradle.kts            # Gradle build config
├── settings.gradle.kts         # Project settings
├── YumehiruCli.main.kts        # Kotlin script (portable)
├── src/main/kotlin/
│   ├── YumehiruApp.kt          # Compose Desktop UI
│   ├── YumehiruCli.kt          # CLI entry point
│   ├── ApiClient.kt            # HTTP API client
│   ├── Models.kt               # Data models
│   └── TTS.kt                  # Text-to-speech
└── README.md
```

## API
Connects to Yumehiru backend at `http://127.0.0.1:18082`
