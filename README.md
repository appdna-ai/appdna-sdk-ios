# AppDNA SDK for iOS

The official iOS SDK for [AppDNA](https://appdna.ai) — the growth console for subscription apps.

## Installation

### Swift Package Manager (Recommended)

In Xcode, go to **File → Add Package Dependencies** and enter:

```
https://github.com/appdna-ai/appdna-sdk-ios.git
```

Select version `1.0.0` or later.

### CocoaPods

```ruby
pod 'AppDNASDK', '~> 1.0'
```

## Quick Start

```swift
import AppDNASDK

// Initialize in AppDelegate or @main App init
AppDNA.configure(apiKey: "YOUR_API_KEY")
```

## Documentation

Full documentation at [docs.appdna.ai](https://docs.appdna.ai/sdks/ios/installation)

## License

MIT — see [LICENSE](LICENSE) for details.
