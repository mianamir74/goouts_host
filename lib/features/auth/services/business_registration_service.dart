import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/business_model.dart';

class BusinessRegistrationService {
  final FirebaseFirestore _firestore;

  BusinessRegistrationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<void> registerBusiness(BusinessModel business) async {
    final DocumentReference<Map<String, dynamic>> docRef =
        _firestore.collection('businesses').doc(business.uid);

    final DocumentSnapshot<Map<String, dynamic>> snapshot = await docRef.get();
    final Map<String, dynamic> existingData = snapshot.data() ?? <String, dynamic>{};
    final Map<String, dynamic> payload = Map<String, dynamic>.from(business.toFirestore());

    payload.remove('password');
    payload.remove('confirmPassword');
    payload['updatedAt'] = FieldValue.serverTimestamp();
    payload['businessProfileVerificationLastUpdatedAt'] = FieldValue.serverTimestamp();

    if (!snapshot.exists || existingData['createdAt'] == null) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['businessProfileVerificationSubmittedAt'] = FieldValue.serverTimestamp();
    }

    await docRef.set(payload, SetOptions(merge: true));
  }
}
