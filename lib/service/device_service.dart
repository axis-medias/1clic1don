import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  static const String _deviceIdKey = 'persistent_device_uuid';
  static final _storage = const FlutterSecureStorage();
  static final _uuid = Uuid();

  /// Récupère (ou crée) l'UUID persistant de l'appareil
  static Future<String> getPersistentDeviceId() async {
    // On essaie de lire d'abord
    String? existingId = await _storage.read(key: _deviceIdKey);

    if (existingId != null && existingId.isNotEmpty) {
      return existingId;
    }

    // Sinon on en génère un nouveau (une seule fois)
    final newId = _uuid.v4();
    await _storage.write(key: _deviceIdKey, value: newId);
    print("✅ Nouveau device_uuid généré et stocké : $newId");
    return newId;
  }

  /// Pour forcer la régénération (ex: bouton "réinitialiser device id" en debug)
  static Future<void> resetDeviceId() async {
    await _storage.delete(key: _deviceIdKey);
  }
}