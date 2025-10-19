import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EmergencyContact {
  final String name;
  final String phone;

  EmergencyContact({required this.name, required this.phone});

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
      };

  static EmergencyContact fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}

class ContactsService {
  static const String _contactsKey = 'emergency_contacts';

  static Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(EmergencyContact.fromJson)
          .where((c) => c.phone.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_contactsKey, encoded);
  }

  static Future<void> addContact(String name, String phone) async {
    final contacts = await getContacts();
    contacts.add(EmergencyContact(name: name, phone: phone));
    await saveContacts(contacts);
  }

  static Future<void> removeContactByPhone(String phone) async {
    final contacts = await getContacts();
    final filtered = contacts.where((c) => c.phone != phone).toList();
    await saveContacts(filtered);
  }

  static Future<EmergencyContact?> getFirstContact() async {
    final contacts = await getContacts();
    if (contacts.isEmpty) return null;
    return contacts.first;
  }

  static Future<List<String>> getRecipientPhones() async {
    final contacts = await getContacts();
    return contacts.map((c) => c.phone).toList();
  }
}