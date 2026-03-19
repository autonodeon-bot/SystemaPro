import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:es_td_ngo_mobile/models/user.dart';
import 'package:es_td_ngo_mobile/services/auth_service.dart';

void main() {
  group('AuthService', () {
    late AuthService auth;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      auth = AuthService();
    });

    group('учётные данные (saveCredentials / getStoredCredentials)', () {
      test('пустой username — ничего не сохраняется', () async {
        await auth.saveCredentials('   ', 'secret');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('offline_username'), isNull);
      });

      test('сохранение и чтение логина и пароля', () async {
        await auth.saveCredentials('engineer1', 'pass123');
        final creds = await auth.getStoredCredentials();
        expect(creds, isNotNull);
        expect(creds!.username, 'engineer1');
        expect(creds.password, 'pass123');
      });

      test('hasStoredCredentials true после saveCredentials', () async {
        await auth.saveCredentials('u', 'p');
        expect(await auth.hasStoredCredentials(), true);
      });

      test('hasStoredCredentials false без сохранения', () async {
        expect(await auth.hasStoredCredentials(), false);
      });
    });

    group('офлайн-пароль (verifyPasswordOffline)', () {
      test('verifyPasswordOffline true после saveCredentials', () async {
        await auth.saveCredentials('user', 'my-password');
        expect(await auth.verifyPasswordOffline('my-password'), true);
        expect(await auth.verifyPasswordOffline('wrong'), false);
      });

      test('verifyPasswordOffline false без хеша', () async {
        expect(await auth.verifyPasswordOffline('x'), false);
      });
    });

    group('сессия после входа (saveUser / токен)', () {
      test('getCurrentUser читает сохранённого пользователя', () async {
        final user = User(
          id: 'id-1',
          username: 'tester',
          email: 't@example.com',
          role: 'engineer',
        );
        await auth.saveUser(user);
        final loaded = await auth.getCurrentUser();
        expect(loaded, isNotNull);
        expect(loaded!.username, 'tester');
        expect(loaded.id, 'id-1');
        expect(loaded.role, 'engineer');
      });

      test('токен сохраняется и отдаётся getToken', () async {
        final user = User(
          id: '1',
          username: 'u',
          token: 'jwt-test-token',
        );
        await auth.saveUser(user);
        expect(await auth.getToken(), 'jwt-test-token');
      });

      test('isAuthenticated true при пользователе и токене', () async {
        final user = User(
          id: '1',
          username: 'u',
          token: 't',
        );
        await auth.saveUser(user);
        expect(await auth.isAuthenticated(), true);
      });

      test('isAuthenticated false без токена', () async {
        final user = User(id: '1', username: 'u');
        await auth.saveUser(user);
        expect(await auth.isAuthenticated(), false);
      });
    });

    group('logout', () {
      test('удаляет токен и пароль из хранилищ', () async {
        final user = User(
          id: '1',
          username: 'u',
          token: 'tok',
        );
        await auth.saveUser(user, passwordHash: 'hashval');
        await auth.saveCredentials('u', 'pw');

        await auth.logout();

        expect(await auth.getToken(), isNull);
        expect(await auth.getStoredCredentials(), isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_token'), isNull);
        expect(prefs.getString('password_hash'), isNull);
      });

      test('после logout пользователь в prefs остаётся', () async {
        final user = User(id: '1', username: 'keepme', token: 't');
        await auth.saveUser(user);
        await auth.logout();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('current_user'), isNotNull);
        final json = jsonDecode(prefs.getString('current_user')!) as Map<String, dynamic>;
        expect(json['username'], 'keepme');
      });
    });

    group('биометрия (флаги в SharedPreferences)', () {
      test('setBiometricEnabled / isBiometricEnabled', () async {
        expect(await auth.isBiometricEnabled(), false);
        await auth.setBiometricEnabled(true);
        expect(await auth.isBiometricEnabled(), true);
        await auth.setBiometricEnabled(false);
        expect(await auth.isBiometricEnabled(), false);
      });
    });

    group('PIN', () {
      test('setPin / verifyPin / clearPin', () async {
        expect(await auth.hasPin(), false);
        await auth.setPin('1234');
        expect(await auth.hasPin(), true);
        expect(await auth.verifyPin('1234'), true);
        expect(await auth.verifyPin('9999'), false);
        await auth.clearPin();
        expect(await auth.hasPin(), false);
      });
    });

    group('getOfflineUsername', () {
      test('возвращает username после saveCredentials', () async {
        await auth.saveCredentials('offline_user', 'p');
        expect(await auth.getOfflineUsername(), 'offline_user');
      });
    });
  });
}
