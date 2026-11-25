import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

import 'local_store.dart';

/// Opens the phone's encrypted database with the key from the Keystore / Keychain.
Future<LocalStore> openEncryptedStore(String key) async {
  final path = p.join(await cipher.getDatabasesPath(), 'eduos.db');
  final db = await cipher.openDatabase(path, password: key, version: 1, onCreate: LocalStore.create);
  return LocalStore(db);
}
