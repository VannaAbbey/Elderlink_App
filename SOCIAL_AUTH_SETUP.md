# Social Authentication Setup Guide

This guide will help you configure Google, Facebook, and Apple Sign-In for the ElderLink app.

## 🚀 Quick Start

The social authentication has been implemented in the backend, but you need to configure each provider with your own credentials.

## 📱 Google Sign-In Setup

### 1. Firebase Console Configuration
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your ElderLink project
3. Navigate to "Authentication" > "Sign-in method"
4. Enable "Google" provider
5. Download the updated `google-services.json` file
6. Replace the existing file in `android/app/google-services.json`

### 2. Get SHA-1 Fingerprint
Run this command in your project directory:
```bash
cd android
./gradlew signingReport
```
Copy the SHA-1 fingerprint and add it to your Firebase project settings.

## 📘 Facebook Sign-In Setup

### 1. Facebook Developer Console
1. Go to [Facebook Developers](https://developers.facebook.com/)
2. Create a new app or use existing one
3. Add "Facebook Login" product
4. Get your App ID and Client Token

### 2. Update Configuration
Edit `android/app/src/main/res/values/strings.xml`:
```xml
<string name="facebook_app_id">YOUR_FACEBOOK_APP_ID</string>
<string name="facebook_client_token">YOUR_FACEBOOK_CLIENT_TOKEN</string>
<string name="fb_login_protocol_scheme">fbYOUR_FACEBOOK_APP_ID</string>
```

### 3. Firebase Console
1. In Firebase Console, enable Facebook provider
2. Enter your Facebook App ID and App Secret

## 🍎 Apple Sign-In Setup

### 1. Apple Developer Console
1. Go to [Apple Developer](https://developer.apple.com/)
2. Navigate to "Certificates, Identifiers & Profiles"
3. Enable "Sign In with Apple" for your App ID
4. Create a Service ID for web authentication

### 2. Firebase Console
1. Enable Apple provider in Firebase
2. Configure with your Apple Team ID and Service ID

## 🔧 Current Implementation Features

### ✅ Implemented Features:
- **Google Sign-In**: Complete backend integration
- **Facebook Sign-In**: Complete backend integration  
- **Apple Sign-In**: Complete backend integration
- **User Document Creation**: Automatic Firestore user document creation
- **Role-Based Navigation**: Users default to 'caregiver' role for social sign-ins
- **Error Handling**: Comprehensive error handling for all providers

### 🎯 How It Works:
1. User taps social media icon (Google/Facebook/Apple)
2. Authentication popup appears
3. User signs in with their social account
4. Firebase creates user account and Firestore document
5. App navigates to appropriate home screen (caregiver/nurse)

### 📋 User Data Stored:
- `uid`: Firebase user ID
- `email`: User's email address
- `firstName`: Extracted from social profile
- `lastName`: Extracted from social profile  
- `role`: Defaults to 'caregiver' (can be updated later)
- `provider`: 'google', 'facebook', or 'apple'
- `createdAt`: Timestamp

## 🔄 Testing Social Authentication

### For Development Testing:
1. **Google**: Works immediately with Firebase setup
2. **Facebook**: Requires Facebook App ID configuration
3. **Apple**: Requires Apple Developer account and proper certificates

### Production Deployment:
- Add your app's package name to all provider configurations
- Configure OAuth redirect URIs
- Add production SHA-1 fingerprints
- Enable providers in Firebase for production environment

## 🐛 Troubleshooting

### Common Issues:
1. **"Google Sign-In Failed"**: Check SHA-1 fingerprint in Firebase
2. **"Facebook Login Error"**: Verify App ID in strings.xml
3. **"Apple Sign-In Unavailable"**: Ensure iOS 13+ and proper certificates

### Debug Tips:
- Check Flutter debug console for detailed error messages
- Verify all provider configurations in Firebase Console
- Ensure internet permissions are properly set

## 📞 Need Help?

The social authentication backend is fully implemented and ready to use. Just configure your provider credentials following this guide and users will be able to sign in with their preferred social accounts!

Remember: Social sign-in users will default to 'caregiver' role and can be changed later through the app's profile management system.
