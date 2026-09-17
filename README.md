# Mobile App - Flutter Photo Management with JWT

## Features
- JWT Authentication (Register, Login, Logout)
- Photo management: take a photo (camera) or pick one (gallery), upload, grid display, full screen view, delete
- Compression before upload (`imageQuality: 80`, `maxWidth: 1920`)
- Secure token storage using SharedPreferences
- Modern Material 3 UI

## Setup

### Prerequisites
- Flutter 3.27+
- Dart 3.2+
- Android Studio / VS Code
- Backend API running on port 3000 (see `../back`)

### Installation

1. Get dependencies:
```bash
flutter pub get
```

2. If the `android/` or `ios/` folders are incomplete, regenerate the missing platform files
(existing files such as `AndroidManifest.xml` and `Info.plist` are kept):
```bash
flutter create --project-name photo_app --platforms android,ios .
```

3. Run the app:
```bash
# Android (emulator uses 10.0.2.2 for host localhost)
flutter run

# iOS Simulator (uses localhost)
flutter run -d ios

# Web
flutter run -d chrome
```

## Configuration

### Backend URL
The backend URL is read from the `.env` file (`API_BASE_URL`), see `.env.example`:

| Environment | `API_BASE_URL` |
|---|---|
| Android emulator | `http://10.0.2.2:3000/api` |
| iOS Simulator / Web / Desktop | `http://localhost:3000/api` |
| Physical device (same Wi-Fi) | `http://<your-computer-ip>:3000/api` |
| Production | `https://your-domain.com/api` |

Photo URLs are built by the backend from the host the app used to call it,
so there is nothing else to configure (no IP to change on the server side).

### Android Cleartext Traffic (HTTP)
For Android 9+ (API 28+), HTTP is blocked by default. The app includes network security config to allow HTTP for the emulator / localhost.

File: `android/app/src/main/res/xml/network_security_config.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">10.0.2.2</domain>
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">127.0.0.1</domain>
    </domain-config>
</network-security-config>
```

On a physical device, add your computer IP (e.g. `192.168.1.10`) to this list.

### Camera / gallery permissions
- Android: no permission needed (`image_picker` uses the system camera app and photo picker)
- iOS: `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` are set in `ios/Runner/Info.plist`

## Project Structure
```
lib/
├── main.dart                   # App entry point
├── config/
│   └── env.dart                # Configuration (.env)
├── models/
│   └── photo.dart              # Photo model
├── services/
│   ├── auth_service.dart       # Authentication (register, login, logout, token storage)
│   └── api_service.dart        # Photo API calls with JWT headers (list, upload, delete)
└── screens/
    ├── login_page.dart         # Login screen
    ├── register_page.dart      # Registration screen
    ├── home_page.dart          # Photo grid with add (camera/gallery) and delete
    └── photo_view_page.dart    # Full screen photo (pinch to zoom)
```

## Usage

1. **Register**: Create a new account with name, email, and password
2. **Login**: Sign in with email and password
3. **Home**: View your photos, add a photo ("Ajouter" button → camera or gallery), delete a photo (trash icon)
4. **View**: Tap a photo to open it full screen (pinch to zoom)
5. **Logout**: Tap logout icon in app bar

## API Integration

### Authentication Flow
```
Register/Login → Backend returns JWT → Store in SharedPreferences → Include in Authorization header
```

### Protected Requests
All photo API calls include:
```
Authorization: Bearer <jwt_token>
```

Uploads are sent as `multipart/form-data` with the field `photo`.

### Endpoints used by the app
| Endpoint | Where |
|---|---|
| `POST /auth/register` | `RegisterPage` → `AuthService.register` |
| `POST /auth/login` | `LoginPage` → `AuthService.login` |
| `GET /auth/me` | `HomePage` (user name in the app bar) → `AuthService.getProfile` |
| `POST /auth/refresh` | automatic on any 401 → `AuthService.refreshSession` |
| `POST /auth/logout` | logout button → `AuthService.logout` (session revoked on the server) |
| `GET /photos` | `HomePage` grid → `ApiService.getPhotos` |
| `GET /photos/:id` | `PhotoViewPage` (fresh details) → `ApiService.getPhoto` |
| `POST /photos` | "Ajouter" button → `ApiService.uploadPhoto` |
| `DELETE /photos/:id` | trash icon → `ApiService.deletePhoto` |
| `GET /uploads/<file>` | `Image.network` (grid + full screen) |

`GET /api/health` is only for monitoring (Docker, hosting) and is not called by the app.

### Token Expiry Handling
Login/register store the access token and the refresh token.
If the access token expires (401), the app calls `POST /auth/refresh` automatically
(only once, even when several requests fail at the same time) and replays the request.
If the refresh token is expired or revoked, the app logs out and redirects to the login screen.

## Tests
```bash
# Widget tests (fake backend)
flutter test

# End-to-end test of the services against the real backend (backend running)
flutter test test/api_e2e_test.dart --dart-define=E2E_API=http://localhost:3000/api
```

## Notes
- **Android emulator**: enable "Webcam0" in the AVD camera settings, or test on a real device.
- **iOS Simulator**: the camera is not available — use the gallery or a physical device.

## Troubleshooting

### Connection Refused
- Ensure backend is running on port 3000
- Check firewall settings
- Verify correct IP address for physical devices

### Photos do not display (broken image)
- On a physical device, the IP must be allowed in `network_security_config.xml` (Android)

### Build Errors
```bash
flutter clean
flutter pub get
flutter run
```
