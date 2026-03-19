import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class FcmService {
  static final FcmService _instance = FcmService._();
  factory FcmService() => _instance;
  FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final ApiService _apiService = ApiService();

  String? _token;

  Future<void> initialize() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        _token = await _messaging.getToken();
        if (_token != null) {
          await _registerToken(_token!);
        }

        _messaging.onTokenRefresh.listen(_registerToken);

        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler);

        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        debugPrint('FCM initialized, token: ${_token?.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('FCM initialization error: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      _token = token;
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('fcm_token');

      if (savedToken != token) {
        await _apiService.registerFcmToken(token);
        await prefs.setString('fcm_token', token);
      }
    } catch (e) {
      debugPrint('Error registering FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message: ${message.notification?.title}');
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tap: ${message.data}');
  }
}
