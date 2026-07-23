import 'package:budget/struct/serverClient.dart';
import 'package:budget/struct/settings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:jwt_decode/jwt_decode.dart';

class ServerAuthResult {
  final bool success;
  final String? errorMessage;

  const ServerAuthResult({required this.success, this.errorMessage});
}

class ServerAuth {
  static bool get isLoggedIn {
    final token = appStateSettings["serverToken"] ?? "";
    if (token.isEmpty) return false;
    try {
      final expiry = Jwt.getExpiryDate(token);
      if (expiry == null) return false;
      return expiry.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static String? get currentUsername {
    final token = appStateSettings["serverToken"] ?? "";
    if (token.isEmpty) return null;
    try {
      final payload = Jwt.parseJwt(token);
      return payload['username'];
    } catch (_) {
      return null;
    }
  }

  static String? get currentUserId {
    final token = appStateSettings["serverToken"] ?? "";
    if (token.isEmpty) return null;
    try {
      final payload = Jwt.parseJwt(token);
      return payload['userId'];
    } catch (_) {
      return null;
    }
  }

  static Future<ServerAuthResult> register(
      String serverUrl, String username, String password) async {
    final urlError = _validateServerUrl(serverUrl);
    if (urlError != null) {
      return ServerAuthResult(success: false, errorMessage: urlError);
    }

    await updateSettings("serverUrl", serverUrl, updateGlobalState: false);

    try {
      final result = await ServerClient.post('/api/auth/register', body: {
        'username': username,
        'password': password,
      });

      if (result['token'] != null) {
        await updateSettings("serverToken", result['token'],
            updateGlobalState: false);
        await updateSettings("isLoggedInToServer", true,
            updateGlobalState: false);
        return ServerAuthResult(success: true);
      }
      return ServerAuthResult(
          success: false,
          errorMessage: result['error']?.toString() ??
              "register-error".tr());
    } on ServerAuthException {
      return ServerAuthResult(
          success: false, errorMessage: "unauthorized".tr());
    } on ServerException catch (e) {
      return ServerAuthResult(success: false, errorMessage: e.message);
    } catch (e) {
      return ServerAuthResult(
          success: false,
          errorMessage: "register-error".tr() + ": " + e.toString());
    }
  }

  static Future<ServerAuthResult> login(
      String serverUrl, String username, String password) async {
    final urlError = _validateServerUrl(serverUrl);
    if (urlError != null) {
      return ServerAuthResult(success: false, errorMessage: urlError);
    }

    await updateSettings("serverUrl", serverUrl, updateGlobalState: false);

    try {
      final result = await ServerClient.post('/api/auth/login', body: {
        'username': username,
        'password': password,
      });

      if (result['token'] != null) {
        await updateSettings("serverToken", result['token'],
            updateGlobalState: false);
        await updateSettings("isLoggedInToServer", true,
            updateGlobalState: false);
        return ServerAuthResult(success: true);
      }
      return ServerAuthResult(
          success: false,
          errorMessage: result['error']?.toString() ?? "login-error".tr());
    } on ServerAuthException {
      return ServerAuthResult(
          success: false, errorMessage: "invalid-credentials".tr());
    } on ServerException catch (e) {
      return ServerAuthResult(success: false, errorMessage: e.message);
    } catch (e) {
      return ServerAuthResult(
          success: false,
          errorMessage: "login-error".tr() + ": " + e.toString());
    }
  }

  static String? _validateServerUrl(String serverUrl) {
    if (serverUrl.trim().isEmpty) return "server-url-required".tr();
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null ||
        (!uri.isScheme("http") && !uri.isScheme("https"))) {
      return "server-url-invalid".tr();
    }
    return null;
  }

  static Future<void> logout() async {
    await updateSettings("serverToken", "", updateGlobalState: false);
    await updateSettings("isLoggedInToServer", false,
        updateGlobalState: false);
  }

  static Future<bool> testConnection(String serverUrl) async {
    final previousUrl = appStateSettings["serverUrl"] ?? "";
    try {
      await updateSettings("serverUrl", serverUrl.trim(),
          updateGlobalState: false);
      final response = await ServerClient.get('/api/health');
      return response['status'] == 'ok';
    } catch (_) {
      return false;
    } finally {
      // Restore previous URL if connection test fails and no login succeeded
      if (previousUrl != serverUrl.trim()) {
        await updateSettings("serverUrl", previousUrl,
            updateGlobalState: false);
      }
    }
  }

  static Future<Map<String, dynamic>?> getMe() async {
    try {
      return await ServerClient.get('/api/auth/me');
    } catch (_) {
      return null;
    }
  }
}
