import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessProfileService {
  final FirebaseFirestore _firestore;

  BusinessProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<bool> businessProfileExists(String uid) async {
    final doc = await _firestore.collection('businesses').doc(uid).get();
    return _isBusinessProfileCompleted(doc);
  }

  Stream<bool> businessProfileExistsStream(String uid) {
    return _firestore
        .collection('businesses')
        .doc(uid)
        .snapshots()
        .map(_isBusinessProfileCompleted);
  }

  bool _isBusinessProfileCompleted(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) {
      return false;
    }

    final data = doc.data();
    if (data == null) {
      return false;
    }

    final registrationCompleted = data['registrationCompleted'] == true;
    final status = (data['status'] ?? '').toString().trim().toUpperCase();
    final hasName = _readString(data, const <String>[
      'fullName',
      'contactPersonName',
      'firstName',
      'surname',
    ]).isNotEmpty;
    final hasBusinessName = _readString(data, const <String>[
      'legalBusinessName',
      'companyName',
    ]).isNotEmpty;
    final hasReferral = _readString(data, const <String>[
      'ownReferralCode',
      'referralCode',
    ]).isNotEmpty;

    return registrationCompleted ||
        ((status == 'REGISTERED' || status == 'APPROVED') && (hasName || hasBusinessName || hasReferral));
  }

  String _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }
}
