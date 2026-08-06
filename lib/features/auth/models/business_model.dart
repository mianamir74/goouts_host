import 'package:cloud_firestore/cloud_firestore.dart';

class BusinessModel {
  final String uid;
  final String accountType;
  final String dashboardRole;
  final String phoneNumber;
  final String prefix;
  final String firstName;
  final String surname;
  final String fullName;
  final String contactPersonName;
  final String email;
  final String legalBusinessName;
  final String companyNumber;
  final String country;
  final String city;
  final String analyticsCountry;
  final String analyticsCity;
  final String postcode;
  final bool postcodeVerified;
  final String postcodeVerificationProvider;
  final String houseNoOrName;
  final String streetName;
  final bool termsAccepted;
  final String status;
  final bool registrationCompleted;
  final String referralCodeUsed;
  final String inviteTokenUsed;
  final String ownReferralCode;
  final String referralCode;
  final String profilePhotoUrl;
  final String selfieUrl;
  final String businessProfileVerificationStatus;
  final String businessProfileVerificationBackendStatus;
  final DateTime? businessProfileVerificationSubmittedAt;
  final DateTime? businessProfileVerificationLastUpdatedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BusinessModel({
    required this.uid,
    required this.accountType,
    required this.dashboardRole,
    required this.phoneNumber,
    required this.prefix,
    required this.firstName,
    required this.surname,
    required this.fullName,
    required this.contactPersonName,
    required this.email,
    required this.legalBusinessName,
    required this.companyNumber,
    required this.country,
    required this.city,
    required this.analyticsCountry,
    required this.analyticsCity,
    required this.postcode,
    required this.postcodeVerified,
    required this.postcodeVerificationProvider,
    required this.houseNoOrName,
    required this.streetName,
    required this.termsAccepted,
    required this.status,
    required this.registrationCompleted,
    required this.referralCodeUsed,
    required this.inviteTokenUsed,
    required this.ownReferralCode,
    required this.referralCode,
    required this.profilePhotoUrl,
    required this.selfieUrl,
    required this.businessProfileVerificationStatus,
    required this.businessProfileVerificationBackendStatus,
    this.businessProfileVerificationSubmittedAt,
    this.businessProfileVerificationLastUpdatedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory BusinessModel.fromMap(Map<String, dynamic> data) {
    final String firstName = _readString(data, const <String>['firstName']);
    final String surname = _readString(data, const <String>['surname']);
    final String fullName = _readString(data, const <String>['fullName']);
    final String contactPersonName = _readString(data, const <String>['contactPersonName']);
    final String ownCode = _readString(data, const <String>['ownReferralCode']);
    final String fallbackCode = _readString(data, const <String>['referralCode']);
    final String resolvedFullName = fullName.isNotEmpty
        ? fullName
        : contactPersonName.isNotEmpty
            ? contactPersonName
            : [firstName, surname].where((part) => part.trim().isNotEmpty).join(' ').trim();

    return BusinessModel(
      uid: _readString(data, const <String>['uid']),
      accountType: _readString(data, const <String>['accountType'], fallback: 'business'),
      dashboardRole: _readString(data, const <String>['dashboardRole'], fallback: 'business'),
      phoneNumber: _readString(data, const <String>['phoneNumber', 'phone']),
      prefix: _readString(data, const <String>['prefix']),
      firstName: firstName,
      surname: surname,
      fullName: resolvedFullName,
      contactPersonName: contactPersonName,
      email: _readString(data, const <String>['email']),
      legalBusinessName: _readString(data, const <String>['legalBusinessName']),
      companyNumber: _readString(data, const <String>['companyNumber']),
      country: _readString(data, const <String>['country']),
      city: _readString(data, const <String>['city']),
      analyticsCountry: _readString(data, const <String>['analyticsCountry']),
      analyticsCity: _readString(data, const <String>['analyticsCity']),
      postcode: _readString(data, const <String>['postcode']),
      postcodeVerified: _readBool(data, const <String>['postcodeVerified']),
      postcodeVerificationProvider: _readString(data, const <String>['postcodeVerificationProvider']),
      houseNoOrName: _readString(data, const <String>['houseNoOrName']),
      streetName: _readString(data, const <String>['streetName']),
      termsAccepted: _readBool(data, const <String>['termsAccepted']),
      status: _readString(data, const <String>['status'], fallback: 'PENDING'),
      registrationCompleted: _readBool(data, const <String>['registrationCompleted'], fallback: true),
      referralCodeUsed: _readString(data, const <String>['referralCodeUsed']),
      inviteTokenUsed: _readString(data, const <String>['inviteTokenUsed']),
      ownReferralCode: ownCode.isNotEmpty ? ownCode : _generateBusinessReferralCode(_readString(data, const <String>['uid'])),
      referralCode: fallbackCode.isNotEmpty ? fallbackCode : (ownCode.isNotEmpty ? ownCode : _generateBusinessReferralCode(_readString(data, const <String>['uid']))),
      profilePhotoUrl: _readString(data, const <String>['profilePhotoUrl']),
      selfieUrl: _readString(data, const <String>['selfieUrl', 'profilePhotoUrl']),
      businessProfileVerificationStatus: _readString(data, const <String>['businessProfileVerificationStatus'], fallback: 'submitted'),
      businessProfileVerificationBackendStatus: _readString(data, const <String>['businessProfileVerificationBackendStatus'], fallback: 'submitted'),
      businessProfileVerificationSubmittedAt: _readDateTime(data, const <String>['businessProfileVerificationSubmittedAt']),
      businessProfileVerificationLastUpdatedAt: _readDateTime(data, const <String>['businessProfileVerificationLastUpdatedAt']),
      createdAt: _readDateTime(data, const <String>['createdAt']),
      updatedAt: _readDateTime(data, const <String>['updatedAt']),
    );
  }

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (contactPersonName.trim().isNotEmpty) return contactPersonName.trim();
    if (legalBusinessName.trim().isNotEmpty) return legalBusinessName.trim();
    return 'Business Partner';
  }

  Map<String, dynamic> toFirestore() {
    final Timestamp now = Timestamp.now();
    final String safeOwnReferralCode = ownReferralCode.trim().isNotEmpty
        ? ownReferralCode.trim().toUpperCase()
        : _generateBusinessReferralCode(uid);

    return <String, dynamic>{
      'uid': uid.trim(),
      'accountType': 'business',
      'dashboardRole': 'business',
      'phoneNumber': phoneNumber.trim(),
      'phone': phoneNumber.trim(),
      'prefix': prefix.trim(),
      'firstName': firstName.trim(),
      'surname': surname.trim(),
      'fullName': displayName,
      'contactPersonName': displayName,
      'email': email.trim().toLowerCase(),
      'legalBusinessName': legalBusinessName.trim(),
      'companyNumber': companyNumber.trim(),
      'country': country.trim(),
      'city': city.trim(),
      'analyticsCountry': analyticsCountry.trim().isNotEmpty ? analyticsCountry.trim() : country.trim(),
      'analyticsCity': analyticsCity.trim().isNotEmpty ? analyticsCity.trim() : city.trim(),
      'postcode': postcode.trim().toUpperCase(),
      'postcodeVerified': postcodeVerified,
      'postcodeVerificationProvider': postcodeVerificationProvider.trim(),
      'houseNoOrName': houseNoOrName.trim(),
      'streetName': streetName.trim(),
      'termsAccepted': termsAccepted,
      'status': status.trim().isNotEmpty ? status.trim().toUpperCase() : 'PENDING',
      'registrationCompleted': registrationCompleted,
      'referralCodeUsed': referralCodeUsed.trim().toUpperCase(),
      'inviteTokenUsed': inviteTokenUsed.trim().toUpperCase(),
      'ownReferralCode': safeOwnReferralCode,
      'referralCode': referralCode.trim().isNotEmpty ? referralCode.trim().toUpperCase() : safeOwnReferralCode,
      'profilePhotoUrl': profilePhotoUrl.trim(),
      'selfieUrl': selfieUrl.trim().isNotEmpty ? selfieUrl.trim() : profilePhotoUrl.trim(),
      'businessProfileVerificationStatus': businessProfileVerificationStatus.trim().isNotEmpty ? businessProfileVerificationStatus.trim().toLowerCase() : 'submitted',
      'businessProfileVerificationBackendStatus': businessProfileVerificationBackendStatus.trim().isNotEmpty ? businessProfileVerificationBackendStatus.trim().toLowerCase() : 'submitted',
      'businessProfileVerificationSubmittedAt': businessProfileVerificationSubmittedAt != null ? Timestamp.fromDate(businessProfileVerificationSubmittedAt!) : now,
      'businessProfileVerificationLastUpdatedAt': businessProfileVerificationLastUpdatedAt != null ? Timestamp.fromDate(businessProfileVerificationLastUpdatedAt!) : now,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : now,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : now,
    };
  }

  static String _readString(Map<String, dynamic> data, List<String> keys, {String fallback = ''}) {
    for (final String key in keys) {
      final dynamic value = data[key];
      if (value == null) continue;
      final String text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static bool _readBool(Map<String, dynamic> data, List<String> keys, {bool fallback = false}) {
    for (final String key in keys) {
      final dynamic value = data[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final String normalized = value.trim().toLowerCase();
        if (normalized == 'true') return true;
        if (normalized == 'false') return false;
      }
    }
    return fallback;
  }

  static DateTime? _readDateTime(Map<String, dynamic> data, List<String> keys) {
    for (final String key in keys) {
      final dynamic value = data[key];
      if (value == null) continue;
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String && value.trim().isNotEmpty) {
        final DateTime? parsed = DateTime.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  static String _generateBusinessReferralCode(String uid) {
    final String cleaned = uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (cleaned.isEmpty) return 'GB000001';
    if (cleaned.length >= 6) return 'GB${cleaned.substring(cleaned.length - 6)}';
    return 'GB${cleaned.padLeft(6, '0')}';
  }
}
