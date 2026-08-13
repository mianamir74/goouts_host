import 'dart:io';
import '../../services/address_lookup_service.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// host_home_screen import removed 10 August 2026. Registration no longer ends
// here — it hands off to HostCreateProfileScreen for the profile picture and
// photo ID, and THAT screen finishes at the home screen.
//
// terms_and_conditions_screen import removed 8 August 2026 with the tick box.
// The only thing that used it here was _openTermsAndConditions, and the terms
// are now shown from the sign-up screen instead — which reads them from
// legal_documents/host_legal, a collection readable before sign-in.
import 'package:auto_size_text/auto_size_text.dart';
import 'package:goouts_host/features/common/goouts_sheet.dart';
import 'package:goouts_host/services/biometric_selfie_inspector.dart';

import '../short_stay/host/host_collection.dart';
import 'host_create_profile_screen.dart';
import 'host_pin_credential.dart';

class BusinessRegistrationScreen extends StatefulWidget {
  const BusinessRegistrationScreen({
    super.key,
    required this.referralCode,
    required this.inviteToken,
  });

  final String referralCode;
  final String inviteToken;

  @override
  State<BusinessRegistrationScreen> createState() =>
      _BusinessRegistrationScreenState();
}

class _BusinessRegistrationScreenState
    extends State<BusinessRegistrationScreen> {
  static const Color _goOutsBlue = Color(0xFF0392CA);
  static const Color _successGreen = Color(0xFF16A34A);
  static const String _defaultBusinessReferralCode = 'GB000001';
  static const String _defaultCountry = 'UNITED KINGDOM';
  static const String _northernIrelandCountry = 'NORTHERN IRELAND';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AddressLookupService _addressService = AddressLookupService();
  final ImagePicker _imagePicker = ImagePicker();

  final List<String> _prefixOptions = <String>['Mr', 'Mrs', 'Miss', 'Ms', 'Dr'];
  final List<String> _countryOptions = <String>[
    _defaultCountry,
    _northernIrelandCountry,
  ];
  final Map<String, List<String>> _cityOptionsByCountry =
      <String, List<String>>{
    _defaultCountry: <String>[
      'London',
      'Manchester',
      'Birmingham',
      'Liverpool',
      'Leeds',
      'Bristol',
      'Sheffield',
      'Nottingham',
      'Leicester',
      'Coventry',
      'Bradford',
      'Newcastle',
      'Oxford',
      'Cambridge',
      'Southampton',
      'Portsmouth',
      'Reading',
      'Luton',
      'Milton Keynes',
      'Derby',
    ],
    _northernIrelandCountry: <String>[
      'Belfast',
      'Derry',
      'Lisburn',
      'Newry',
      'Bangor',
      'Craigavon',
      'Newtownabbey',
      'Carrickfergus',
      'Antrim',
      'Coleraine',
      'Omagh',
      'Enniskillen',
      'Armagh',
      'Dungannon',
      'Ballymena',
      'Larne',
    ],
  };

  String? _selectedPrefix;
  String? _selectedCountry;
  String? _selectedCity;

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _confirmEmailController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  final FocusNode _confirmPinFocusNode = FocusNode();
  final TextEditingController _legalBusinessNameController =
      TextEditingController();
  final TextEditingController _companyNumberController =
      TextEditingController();
  final TextEditingController _shopUnitNoController = TextEditingController();
  final TextEditingController _roadNameController = TextEditingController();
  final TextEditingController _townController = TextEditingController();
  final TextEditingController _postcodeController = TextEditingController();

  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _isLoading = false;
  bool _isPickingSelfie = false;
  bool _showSelfieError = false;
  bool _isPostcodeVerified = false;
  bool _isConfirmingPostcode = false;
  bool _isUpdatingPostcodeProgrammatically = false;

  // ── Smart Hybrid verified data (May 2026) ──
  String _verifiedUprn = '';
  String _verifiedFullAddress = '';
  double? _verifiedLatitude;
  double? _verifiedLongitude;
  // Locked only when address was actually auto-filled from OS bottom sheet.
  bool _addressFieldsLocked = false;
  List<MapboxSuggestResult> _addressSuggestions = [];
  String _mapboxSessionToken = AddressLookupService.generateSessionToken();
  bool _isLookingUpAddress = false;

  XFile? _selfieImage;

  /// Confidence scores for the accepted selfie, kept so the NEXT screen can
  /// hand them to the server-side KYC engine alongside the document scores.
  ///
  /// Carried in memory rather than re-scored later, because by the time the
  /// profile screen runs the selfie has already been uploaded and the local
  /// file may be gone — image_picker writes to a cache directory the OS is
  /// free to clear.
  Map<String, dynamic>? _selfieScores;

  @override
  void initState() {
    super.initState();
    _selectedPrefix = _prefixOptions.first;
    _selectedCountry = _countryOptions.first;
    _postcodeController.addListener(_handlePostcodeEdited);
    _pinFocusNode.addListener(() => setState(() {}));
    _confirmPinFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _postcodeController.removeListener(_handlePostcodeEdited);
    _pinFocusNode.dispose();
    _confirmPinFocusNode.dispose();
    _firstNameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _confirmEmailController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _legalBusinessNameController.dispose();
    _companyNumberController.dispose();
    _shopUnitNoController.dispose();
    _roadNameController.dispose();
    _townController.dispose();
    _postcodeController.dispose();
    super.dispose();
  }

  List<String> _cityOptionsForSelectedCountry() {
    return _cityOptionsByCountry[_selectedCountry] ?? <String>[];
  }

  void _handlePostcodeEdited() {
    if (_isUpdatingPostcodeProgrammatically) {
      return;
    }

    final String rawPostcode = _postcodeController.text.trim();
    final String inferredCountry = rawPostcode.isEmpty
        ? _countryOptions.first
        : _inferCountryFromPostcode(rawPostcode);

    setState(() {
      _isPostcodeVerified = false;
      _verifiedUprn = '';
      _verifiedFullAddress = '';
      _verifiedLatitude = null;
      _verifiedLongitude = null;
      _addressFieldsLocked = false;
      if (_selectedCountry != inferredCountry) {
        _selectedCountry = inferredCountry;
        _selectedCity = null;
      }
    });
  }

  String _normalizeUkPostcode(String input) {
    final String cleaned =
        input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length <= 3) {
      return cleaned;
    }
    return '${cleaned.substring(0, cleaned.length - 3)} ${cleaned.substring(cleaned.length - 3)}';
  }

  String? _postcodeValidatorLocal(String? value) {
    final String normalized = _normalizeUkPostcode(value ?? '').trim();
    if (normalized.isEmpty) {
      return 'Postcode is required';
    }
    final RegExp regex =
        RegExp(r'^[A-Z]{1,2}[0-9][A-Z0-9]?\s?[0-9][A-Z]{2}$');
    if (!regex.hasMatch(normalized)) {
      return 'Enter a valid UK postcode';
    }
    return null;
  }

  String _normalizedPostcode() => _normalizeUkPostcode(_postcodeController.text);

  String _inferCountryFromPostcode(String postcode) {
    final String normalized = _normalizeUkPostcode(postcode).replaceAll(' ', '');
    if (normalized.startsWith('BT')) {
      return _northernIrelandCountry;
    }
    return _defaultCountry;
  }

  String _normalizeForMatching(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  String? _matchCityOption(String? rawCity, List<String> options) {
    final String input = _normalizeForMatching(rawCity ?? '');
    if (input.isEmpty) {
      return null;
    }
    for (final String option in options) {
      final String normalizedOption = _normalizeForMatching(option);
      if (normalizedOption == input ||
          normalizedOption.contains(input) ||
          input.contains(normalizedOption)) {
        return option;
      }
    }
    return null;
  }

  void _showSnackBarMessage(String message) {
    if (!mounted) return;
    GoOutsSheet.warning(context, title: 'Attention', message: message);
  }

  Future<void> _pickSelfie() async {
    try {
      setState(() {
        _isPickingSelfie = true;
      });

      final XFile? pickedImage = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1200,
      );

      if (!mounted) {
        return;
      }

      if (pickedImage != null) {
        // ── CHECK THE FACE BEFORE ACCEPTING THE PHOTO ────────────────────
        //
        // Added 13 August 2026. Until now the host's selfie was captured and
        // uploaded with NO validation at all — not even the brightness and
        // blur checks the consumer and driver apps had. Whatever the camera
        // returned went straight to Storage and an admin eyeballed it days
        // later, if they looked at all.
        //
        // Now ML Kit answers the only question that matters before the photo
        // is kept: is there one person in this, facing the camera, eyes open,
        // face not covered. A wall, a shoe or a ceiling is refused here.
        //
        // Nothing biometric is stored — the detector returns numbers and the
        // face data is discarded. See services/face_check_service.dart.
        final Map<String, dynamic> check =
            await BiometricSelfieInspector().inspectSelfie(pickedImage.path);
        if (!mounted) {
          return;
        }

        if (check['isValid'] != true) {
          await GoOutsSheet.warning(
            context,
            title: 'Retake your selfie',
            message: (check['errorMessage'] as String?) ??
                'That photo could not be used. Please take it again.',
          );
          if (!mounted) {
            return;
          }
          // Deliberately NOT stored. Keeping a refused selfie would let the
          // host tap Continue with a photo we have already rejected.
          return;
        }

        setState(() {
          _selfieImage = pickedImage;
          _showSelfieError = false;
          _selfieScores =
              Map<String, dynamic>.from(check['scores'] as Map? ?? const {});
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Selfie Error'),
            content: Text('Failed to capture selfie.\n\n$e'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } finally {
      // Guard the setState rather than returning. A bare `return` in a finally
      // block discards any exception still propagating out of the try, so a
      // failed selfie capture would vanish instead of reaching Crashlytics.
      if (mounted) {
        setState(() {
          _isPickingSelfie = false;
        });
      }
    }
  }

  Future<String> _uploadSelfie({
    required String uid,
    required XFile selfieImage,
  }) async {
    final Reference ref = FirebaseStorage.instance
        .ref()
        .child('stay_hosts')
        .child('selfies')
        .child('$uid.jpg');
    await ref.putFile(File(selfieImage.path));
    return ref.getDownloadURL();
  }

  /// Smart Hybrid Address Lookup (May 2026).
  ///
  /// Two-Step Professional flow:
  ///   1. Validate postcode
  ///   2. Fetch all OS addresses for the postcode
  ///   3. Show a bottom sheet for the owner to pick the correct one
  ///   4. Show a brief "Verifying with Official Address Register..." overlay
  ///   5. Fill the form and lock the fields with UPRN + lat/lng captured
  /// Links an email+password credential to the current Firebase phone-auth
  /// account so returning users can sign in with password instead of SMS OTP.
  /// Silently ignores errors (e.g. credential already linked).
  Future<void> _linkEmailPasswordCredential({
    required User currentUser,
    required String password,
  }) async {
    try {
      final String phone = currentUser.phoneNumber ?? '';
      // hostAuthEmail / hostPinPassword — see host_pin_credential.dart.
      //
      // The password MUST go through hostPinPassword. Firebase rejects
      // anything under 6 characters, and a raw 4-digit PIN is four, so the
      // previous version of this method threw weak-password on EVERY
      // registration and the catch below hid it. No host has ever had a
      // working PIN because of this one line.
      final AuthCredential cred = EmailAuthProvider.credential(
        email: hostAuthEmail(phone),
        password: hostPinPassword(password),
      );
      await currentUser.linkWithCredential(cred);
      debugPrint('host PIN credential linked for $phone');
    } on FirebaseAuthException catch (e) {
      // NOT silent any more. 'provider-already-linked' is genuinely fine and
      // stays quiet; anything else is a host who will not be able to sign in
      // with their PIN, and we want that in the logs rather than invisible.
      if (e.code != 'provider-already-linked' &&
          e.code != 'credential-already-in-use') {
        debugPrint('host PIN credential link FAILED: ${e.code} ${e.message}');
      }
    } catch (e) {
      debugPrint('host PIN credential link FAILED: $e');
    }
  }

  Future<void> _confirmPostcode() async {
    FocusScope.of(context).unfocus();

    final String? postcodeError =
        _postcodeValidatorLocal(_postcodeController.text);
    if (postcodeError != null) {
      setState(() {
        _isPostcodeVerified = false;
      });
      _showSnackBarMessage('Please enter a valid postcode before continuing.');
      return;
    }

    final String shopUnitNo = _shopUnitNoController.text.trim();
    if (shopUnitNo.isEmpty) {
      _showSnackBarMessage(
        'Please enter your Shop/Unit No first, then look up your address.',
      );
      return;
    }

    final String postcode = _normalizedPostcode();
    _isUpdatingPostcodeProgrammatically = true;
    _postcodeController.text = postcode;
    _postcodeController.selection = TextSelection.collapsed(
      offset: _postcodeController.text.length,
    );
    _isUpdatingPostcodeProgrammatically = false;

    setState(() {
      _isConfirmingPostcode = true;
    });

    try {
      // Mapbox reliably matches a SPECIFIC building when given
      // "{shop/unit no} {postcode}" together — a bare postcode alone only
      // ever resolves to the postcode's centroid, never a per-building list.
      final List<MapboxSuggestResult> results = await _addressService.suggest(
        '$shopUnitNo $postcode',
        _mapboxSessionToken,
      );

      if (!mounted) return;

      if (results.isNotEmpty) {
        setState(() {
          _isConfirmingPostcode = false;
          _addressSuggestions = results;
        });
        return;
      }

      setState(() {
        _isConfirmingPostcode = false;
        _isPostcodeVerified = false;
        _addressFieldsLocked = false;
      });
      _showSnackBarMessage(
        'Address not found. Please check it or tap "Enter manually" below.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConfirmingPostcode = false;
        _isPostcodeVerified = false;
      });
      _showSnackBarMessage(
        'We could not verify this address right now. Please try again.',
      );
    }
  }

  /// Called when the owner taps a suggestion from the address dropdown.
  /// Retrieves full details (street, coords, etc.) and auto-fills everything.
  Future<void> _onSuggestionSelected(MapboxSuggestResult suggestion) async {
    setState(() {
      _isLookingUpAddress = true;
      _addressSuggestions = [];
    });
    final MapboxAddressResult? address = await _addressService.retrieve(
      suggestion.mapboxId,
      _mapboxSessionToken,
    );
    // retrieve() is the billed call — rotate the token so the NEXT lookup
    // starts a fresh free suggest() session.
    _mapboxSessionToken = AddressLookupService.generateSessionToken();

    if (!mounted) return;

    if (address == null) {
      setState(() => _isLookingUpAddress = false);
      _showSnackBarMessage('Could not load that address — please try again.');
      return;
    }

    _onAddressSelected(address);
    setState(() => _isLookingUpAddress = false);
  }

  /// Fills every address field from a fully-resolved Mapbox result.
  void _onAddressSelected(MapboxAddressResult address) {
    final String resolvedCountry = _inferCountryFromPostcode(address.postcode);
    final List<String> cityOptions = _cityOptionsByCountry[resolvedCountry] ?? <String>[];
    final String? inferredCity = AddressLookupService.inferCityFromPostcode(address.postcode);
    final String? matchedCity = inferredCity != null
        ? _matchCityOption(inferredCity, cityOptions)
        : (address.city.isNotEmpty ? _matchCityOption(address.city, cityOptions) : null);
    setState(() {
      _postcodeController.text   = address.postcode;
      _shopUnitNoController.text = address.houseNumber?.isNotEmpty == true
          ? address.houseNumber!
          : _shopUnitNoController.text;
      _roadNameController.text          = address.street ?? '';
      _townController.text       = (address.town ?? address.city).toUpperCase();
      _selectedCountry           = resolvedCountry;
      _selectedCity              = matchedCity;
      _verifiedFullAddress       = address.fullAddress;
      _verifiedLatitude          = address.latitude;
      _verifiedLongitude         = address.longitude;
      _isPostcodeVerified        = true;
      _addressFieldsLocked       = false;
      _addressSuggestions        = [];
    });
  }

  /// Tapped when the owner picks "Edit manually". Clears verified state.
  void _handleEditManually() {
    setState(() {
      _isPostcodeVerified = false;
      _verifiedUprn = '';
      _verifiedFullAddress = '';
      _verifiedLatitude = null;
      _verifiedLongitude = null;
      _addressFieldsLocked = false;
    });
    _showSnackBarMessage(
      'Address fields are now editable. Re-tap "Find Official Address" to re-verify.',
    );
  }

    String _normalizeInviteToken(String inviteToken) {
    return inviteToken.trim().toUpperCase();
  }

  String _normalizeReferralCode(String referralCode) {
    final String cleaned = referralCode.trim().toUpperCase();
    if (cleaned.isEmpty || !cleaned.startsWith('GB')) {
      return _defaultBusinessReferralCode;
    }
    return cleaned;
  }

  String _titleCase(String value) {
    if (value.trim().isEmpty) {
      return '';
    }
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .map((String word) {
          if (word.isEmpty) {
            return word;
          }
          final String lower = word.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }

  String _generateBusinessReferralCode(String uid) {
    final String cleaned =
        uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    if (cleaned.isEmpty) {
      return _defaultBusinessReferralCode;
    }
    if (cleaned.length >= 6) {
      return 'GB${cleaned.substring(cleaned.length - 6)}';
    }
    return 'GB${cleaned.padLeft(6, '0')}';
  }

  bool _hasText(TextEditingController controller) {
    return controller.text.trim().isNotEmpty;
  }

  bool get _isPrefixComplete => (_selectedPrefix ?? '').trim().isNotEmpty;

  bool get _isFirstNameComplete => _firstNameController.text.trim().length >= 2;

  bool get _isSurnameComplete => _surnameController.text.trim().length >= 2;

  bool get _isEmailComplete {
    final String email = _emailController.text.trim();
    final RegExp emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(email);
  }

  bool get _isConfirmEmailComplete {
    final String email = _emailController.text.trim();
    final String confirmEmail = _confirmEmailController.text.trim();
    final RegExp emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(email) && confirmEmail == email;
  }

  bool get _isPinComplete {
    final String pin = _pinController.text;
    return pin.length == 4 && RegExp(r'^\d{4}$').hasMatch(pin);
  }

  bool get _isConfirmPinComplete {
    return _isPinComplete && _confirmPinController.text == _pinController.text;
  }

  bool get _isBusinessNameComplete =>
      _legalBusinessNameController.text.trim().length >= 2;

  bool get _isCompanyNumberComplete {
    final String value = _companyNumberController.text.trim().toUpperCase();
    final RegExp companyNumberRegex = RegExp(
      r'^(?:\d{8}|SC\d{6}|NI\d{6})$',
      caseSensitive: false,
    );
    return companyNumberRegex.hasMatch(value);
  }

  bool get _isShopUnitComplete => _hasText(_shopUnitNoController);
  bool get _isRoadNameComplete => _roadNameController.text.trim().length >= 2;
  bool get _isCountryComplete => (_selectedCountry ?? '').trim().isNotEmpty;
  bool get _isCityComplete => (_selectedCity ?? '').trim().isNotEmpty;
  bool get _isSelfieComplete => _selfieImage != null;

  Widget _successIcon(bool show) {
    if (!show) {
      return const SizedBox.shrink();
    }
    return const Icon(
      Icons.verified_rounded,
      color: _successGreen,
      size: 20,
    );
  }

  Future<void> _submitBusinessForm() async {
    FocusScope.of(context).unfocus();

    final bool isFormValid = _formKey.currentState?.validate() ?? false;
    if (!isFormValid) {
      _showSnackBarMessage(
        'Please complete all required fields before continuing.',
      );
      return;
    }

    if (!_isPostcodeVerified) {
      _showSnackBarMessage('Please confirm your postcode before continuing.');
      return;
    }

    if (_selectedCountry == null || _selectedCountry!.trim().isEmpty) {
      _showSnackBarMessage('Please select your country.');
      return;
    }

    if (_selectedCity == null || _selectedCity!.trim().isEmpty) {
      _showSnackBarMessage('Please select your city.');
      return;
    }

    if (_selfieImage == null) {
      setState(() {
        _showSelfieError = true;
      });
      _showSnackBarMessage('Please capture your selfie before continuing.');
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Not Logged In'),
            content: const Text(
              'No authenticated business user was found. Please log in again.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return;
    }

    final String inviteToken = _normalizeInviteToken(widget.inviteToken);
    final String normalizedReferralCode =
        _normalizeReferralCode(widget.referralCode);

    setState(() {
      _isLoading = true;
    });

    try {
      final String profilePhotoUrl = await _uploadSelfie(
        uid: currentUser.uid,
        selfieImage: _selfieImage!,
      );

      final DateTime now = DateTime.now();
      final String firstName = _firstNameController.text.trim();
      final String surname = _surnameController.text.trim();
      final String fullName = _titleCase('$firstName $surname'.trim());
      final String ownReferralCode =
          _generateBusinessReferralCode(currentUser.uid);

      final Map<String, dynamic> businessData = <String, dynamic>{
        'uid': currentUser.uid,
        'accountType': 'business',
        'dashboardRole': 'business',
        'phoneNumber': currentUser.phoneNumber ?? '',
        'prefix': (_selectedPrefix ?? '').trim(),
        'firstName': firstName,
        'middleName': '',
        'surname': surname,
        'fullName': fullName,
        'contactPersonName': fullName,
        'email': _emailController.text.trim(),
        'legalBusinessName': _legalBusinessNameController.text.trim(),
        'companyNumber': _companyNumberController.text.trim().toUpperCase(),
        'country': _selectedCountry?.trim() ?? '',
        'city': _selectedCity?.trim() ?? '',
        'analyticsCountry': _selectedCountry?.trim() ?? '',
        'analyticsCity': _selectedCity?.trim() ?? '',
        'postcode': _normalizedPostcode(),
        'postcodeVerified': _isPostcodeVerified,
        'postcodeVerificationProvider':
            _isPostcodeVerified ? 'os_mapbox_hybrid' : '',
        'addressUprn': _verifiedUprn,
        'addressFull': _verifiedFullAddress,
        'addressLatitude': _verifiedLatitude,
        'addressLongitude': _verifiedLongitude,
        'shopUnitNo': _shopUnitNoController.text.trim(),
        'roadName': _roadNameController.text.trim(),
        'town': _townController.text.trim().toUpperCase(),
        'termsAccepted': true,
        'status': 'PENDING',
        'registrationCompleted': true,
        'referralCodeUsed': normalizedReferralCode,
        'inviteTokenUsed': inviteToken,
        'ownReferralCode': ownReferralCode,
        'referralCode': ownReferralCode,
        'profilePhotoUrl': profilePhotoUrl,
        'selfieUrl': profilePhotoUrl,
        'businessProfileVerificationStatus': 'submitted',
        'businessProfileVerificationBackendStatus': 'submitted',
        'businessProfileVerificationSubmittedAt': FieldValue.serverTimestamp(),
        'businessProfileVerificationLastUpdatedAt':
            FieldValue.serverTimestamp(),
        'createdAt': now,
        'updatedAt': now,
      };

      if (_isPostcodeVerified) {
        businessData['postcodeVerifiedAt'] = FieldValue.serverTimestamp();
      }

      // ── DO NOT SEND ADMIN-OWNED FIELDS ON A RE-SUBMISSION ────────────────
      //
      // ADDED 8 August 2026.
      //
      // firestore.rules guards /stay_hosts updates with selfEditAllowed, which
      // refuses ANY write touching driverProtectedFields() — a list that
      // includes `status`. And it refuses the WHOLE write, not the offending
      // field.
      //
      // First registration is a `create`, which has no field restrictions, so
      // sending status: 'PENDING' there is fine and it is how the record gets
      // its initial state.
      //
      // But a host who comes back to correct a typo AFTER you have approved
      // them is doing an `update` that changes status from APPROVED back to
      // PENDING. Firestore denies it, and every other correction they made in
      // the same form dies with it — with an error that says permission denied
      // and nothing about which field caused it.
      //
      // So: strip the admin-owned keys when the record already exists. The
      // server and the admin panel own verification state; the host owns their
      // details.
      final existing = await FirebaseFirestore.instance
          .collection(kStayHostsCollection)
          .doc(currentUser.uid)
          .get();

      if (existing.exists) {
        // Mirrors driverProtectedFields() in firestore.rules. If that list
        // changes, this changes.
        for (final k in const <String>[
          'status',
          'kycStatus',
          'accountStatus',
          'isActive',
          'role',
          'rating',
          'verified',
          'approved',
          'walletBalance',
          'adminManualVerification',
          'overallResult',
        ]) {
          businessData.remove(k);
        }
      }

      await FirebaseFirestore.instance
          .collection(kStayHostsCollection)
          .doc(currentUser.uid)
          .set(businessData, SetOptions(merge: true));

      // Link email+password so returning users can log in without SMS OTP
      await _linkEmailPasswordCredential(
        currentUser: currentUser,
        password: _pinController.text,
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Details received'),
            content: const SingleChildScrollView(
              child: Text(
                'Thanks. Your personal details, business details, address and '
                'selfie are saved.\n\nOne more step: a profile picture and a '
                'photo ID, which the law requires us to hold before you can '
                'take bookings.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      // ── ⚠ GOES TO KYC, NOT STRAIGHT HOME. Changed 10 August 2026. ────────
      //
      // This used to push HostHomeScreen and finish. HostCreateProfileScreen
      // was written on 9 August and committed in build 10, and NOTHING
      // NAVIGATED TO IT — it shipped as dead code, so a host saw no change at
      // all and registration ended with no identity document on file.
      //
      // That matters beyond a missing screen. The auto-KYC engine weights
      // document quality at 0.50 of the score; with no document the ceiling is
      // 0.50 against a 0.65 manual-review floor. Until this screen runs, every
      // host is unverifiable by anything except an admin doing it by hand.
      //
      // pushAndRemoveUntil, not push: the eight registration screens must not
      // stay on the stack. Back from here should not walk a host through a
      // form they have already submitted, and a second submit would write the
      // record twice.
      //
      // HostCreateProfileScreen itself ends at HostHomeScreen, so the journey
      // still finishes in the same place.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => HostCreateProfileScreen(
            selfieScores: _selfieScores,
          ),
        ),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error'),
            content: Text('Failed to save business registration.\n\n$e'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } finally {
      // Same reason as _pickSelfie above — a bare return here would swallow a
      // failure to submit the registration, which is the single most important
      // error in this app to not lose.
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: _goOutsBlue, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: Colors.red, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }

  InputDecoration _completedInputDecoration({
    required String label,
    required bool complete,
    String? hint,
    Widget? suffixIcon,
    String? helperText,
  }) {
    return _inputDecoration(
      label: label,
      hint: hint,
      suffixIcon: suffixIcon ?? _successIcon(complete),
      helperText: helperText,
    );
  }

  String? _requiredValidator(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    final String email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email is required';
    }
    final RegExp emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _confirmEmailValidator(String? value) {
    final String confirmEmail = value?.trim() ?? '';
    if (confirmEmail.isEmpty) {
      return 'Confirm Email is required';
    }
    if (_emailValidator(_emailController.text) != null) {
      return 'Enter a valid email first';
    }
    if (confirmEmail != _emailController.text.trim()) {
      return 'Email addresses do not match';
    }
    return null;
  }

  String? _pinValidator(String? value) {
    if (value == null || value.isEmpty) return 'PIN is required';
    if (value.length < 4) return 'PIN must be 4 digits';
    if (!RegExp(r'^\d{4}$').hasMatch(value)) return 'PIN must contain digits only';
    return null;
  }

  String? _confirmPinValidator(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your PIN';
    if (value != _pinController.text) return 'PINs do not match';
    return null;
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6ECF1)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AutoSizeText(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 6),
          AutoSizeText(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> cityOptions = _cityOptionsForSelectedCountry();

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: _goOutsBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Business Registration',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: <Widget>[
              _buildSectionCard(
                title: 'Business Partner Details',
                subtitle: 'Complete your business registration details below.',
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPrefix,
                    decoration: _completedInputDecoration(
                      label: 'Prefix',
                      complete: _isPrefixComplete,
                    ),
                    items: _prefixOptions
                        .map(
                          (String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      setState(() {
                        _selectedPrefix = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _firstNameController,
                    decoration: _completedInputDecoration(
                      label: 'First Name',
                      complete: _isFirstNameComplete,
                    ),
                    validator: (String? value) =>
                        _requiredValidator(value, 'First Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _surnameController,
                    decoration: _completedInputDecoration(
                      label: 'Surname',
                      complete: _isSurnameComplete,
                    ),
                    validator: (String? value) =>
                        _requiredValidator(value, 'Surname'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _completedInputDecoration(
                      label: 'Email',
                      complete: _isEmailComplete,
                    ),
                    validator: _emailValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _completedInputDecoration(
                      label: 'Confirm Email',
                      complete: _isConfirmEmailComplete,
                    ),
                    validator: _confirmEmailValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(letterSpacing: 10, fontSize: 18),
                    decoration: _completedInputDecoration(
                      label: '4-digit PIN',
                      complete: _isPinComplete,
                      helperText: 'You will use this PIN to log in',
                    ).copyWith(
                      counterText: '',
                      suffixIconConstraints: const BoxConstraints(
                        minHeight: 0,
                        minWidth: 0,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_isPinComplete &&
                              !_pinFocusNode.hasFocus)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePin = !_obscurePin;
                              });
                            },
                            icon: Icon(
                              _obscurePin
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    validator: _pinValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPinController,
                    focusNode: _confirmPinFocusNode,
                    obscureText: _obscureConfirmPin,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(letterSpacing: 10, fontSize: 18),
                    decoration: _completedInputDecoration(
                      label: 'Confirm PIN',
                      complete: _isConfirmPinComplete,
                    ).copyWith(
                      counterText: '',
                      suffixIconConstraints: const BoxConstraints(
                        minHeight: 0,
                        minWidth: 0,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_isConfirmPinComplete &&
                              !_confirmPinFocusNode.hasFocus)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPin =
                                    !_obscureConfirmPin;
                              });
                            },
                            icon: Icon(
                              _obscureConfirmPin
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    validator: _confirmPinValidator,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _legalBusinessNameController,
                    decoration: _completedInputDecoration(
                      label: 'Legal Business Name',
                      complete: _isBusinessNameComplete,
                    ),
                    validator: (String? value) =>
                        _requiredValidator(value, 'Legal Business Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _companyNumberController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                      LengthLimitingTextInputFormatter(8),
                      UpperCaseTextFormatter(),
                    ],
                    decoration: _completedInputDecoration(
                      label: 'Company Registration No',
                      complete: _isCompanyNumberComplete,
                    ),
                    validator: (String? value) =>
                        _requiredValidator(value, 'Company Registration No'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              _buildSectionCard(
                title: 'Business Address',
                subtitle:
                    'Enter your Shop/Unit No and postcode → tap "Look Up Address" → pick from the list.',
                children: <Widget>[
                  // ── Loading bar while OS lookup runs ───────────────────
                  if (_isConfirmingPostcode)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        color: _goOutsBlue,
                        backgroundColor: Color(0xFFE5F4FB),
                      ),
                    ),

                  // ── Shop/Unit No — typed FIRST, needed to search Mapbox ─
                  TextFormField(
                    controller: _shopUnitNoController,
                    readOnly: _addressFieldsLocked,
                    decoration: _completedInputDecoration(
                      label: 'Shop/Unit No',
                      complete: _isShopUnitComplete,
                      helperText: _addressFieldsLocked
                          ? 'Auto-filled from official record'
                          : null,
                    ),
                    validator: (String? value) =>
                        _requiredValidator(value, 'Shop/Unit No'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // ── Postcode + Find button (side by side) ──────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          controller: _postcodeController,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9 ]')),
                            LengthLimitingTextInputFormatter(8),
                            UpperCaseTextFormatter(),
                          ],
                          decoration: _completedInputDecoration(
                            label: 'Postcode',
                            complete: _isPostcodeVerified,
                          ),
                          validator: _postcodeValidatorLocal,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 58,
                          child: ElevatedButton.icon(
                            onPressed: (_isConfirmingPostcode || _isLookingUpAddress)
                                ? null
                                : _confirmPostcode,
                            icon: _isConfirmingPostcode
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _isPostcodeVerified
                                        ? Icons.verified_rounded
                                        : Icons.search_rounded,
                                  ),
                            label: AutoSizeText(
                              _isPostcodeVerified
                                  ? 'Verified'
                                  : 'Look Up Address',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isPostcodeVerified
                                  ? _successGreen
                                  : _goOutsBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),

                  // ── Address dropdown (after Look Up returns results) ────
                  if (_addressSuggestions.isNotEmpty) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Color(0xFF0392CA).withValues(alpha: 0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                            child: Text(
                              'Select your address:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          ..._addressSuggestions.map((s) => InkWell(
                            onTap: () => _onSuggestionSelected(s),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      color: Color(0xFF0392CA), size: 16),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0D1B3E),
                                          ),
                                        ),
                                        Text(
                                          s.placeFormatted,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: Colors.grey, size: 16),
                                ],
                              ),
                            ),
                          )),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_isLookingUpAddress) ...[
                    const Row(
                      children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading address…', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Verified subtitle / Manual entry link ──────────────
                  if (_isPostcodeVerified)
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.shield_rounded,
                          size: 16,
                          color: _successGreen,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Official UPRN Address Verified',
                            style: TextStyle(
                              color: _successGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _isConfirmingPostcode
                              ? null
                              : _handleEditManually,
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: _goOutsBlue,
                          ),
                          child: AutoSizeText(
                            'Edit manually',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _isConfirmingPostcode
                            ? null
                            : _handleEditManually,
                        icon: Icon(Icons.edit_rounded, size: 16),
                        label: AutoSizeText(
                          "Can't find your address? Enter manually",
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: _goOutsBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // ── Road Name ─────────────────────────────────────────
                  TextFormField(
                    controller: _roadNameController,
                    readOnly: _addressFieldsLocked,
                    decoration: _completedInputDecoration(
                      label: 'Street / Road Name',
                      complete: _isRoadNameComplete,
                    ),
                    validator: (String? value) =>
                        _requiredValidator(value, 'Street / Road Name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // ── Town (auto-filled from Mapbox) ────────────────────
                  TextFormField(
                    controller: _townController,
                    decoration: _completedInputDecoration(
                      label: 'Town',
                      complete: _townController.text.trim().isNotEmpty,
                      helperText: _isPostcodeVerified &&
                              _townController.text.trim().isNotEmpty
                          ? 'Auto-filled from postcode'
                          : null,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (String? value) =>
                        _requiredValidator(value, 'Town'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),

                  // ── City ──────────────────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: cityOptions.contains(_selectedCity) ? _selectedCity : null,
                    decoration: _completedInputDecoration(
                      label: 'City',
                      complete: _isCityComplete,
                    ),
                    items: cityOptions
                        .map(
                          (String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      setState(() {
                        _selectedCity = value;
                      });
                    },
                    validator: (String? value) =>
                        _requiredValidator(value, 'City'),
                  ),
                  const SizedBox(height: 12),

                  // ── Country ───────────────────────────────────────────
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCountry,
                    decoration: _completedInputDecoration(
                      label: 'Country',
                      complete: _isCountryComplete,
                    ),
                    items: _countryOptions
                        .map(
                          (String value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) {
                      setState(() {
                        _selectedCountry = value;
                        _selectedCity = null;
                        _isPostcodeVerified = false;
                        _verifiedUprn = '';
                        _verifiedFullAddress = '';
                        _verifiedLatitude = null;
                        _verifiedLongitude = null;
                      });
                    },
                    validator: (String? value) =>
                        _requiredValidator(value, 'Country'),
                  ),
                ],
              ),
              _buildSectionCard(
                title: 'Selfie Verification',
                subtitle:
                    'Please capture a clear selfie for business profile verification.',
                children: <Widget>[
                  if (_selfieImage != null)
                    Container(
                      clipBehavior: Clip.antiAlias,
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        image: DecorationImage(
                          image: FileImage(File(_selfieImage!.path)),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Container(
                      clipBehavior: Clip.antiAlias,
                      width: double.infinity,
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4FAFD),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _showSelfieError
                              ? Colors.red
                              : const Color(0xFFE6ECF1),
                        ),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(
                            Icons.camera_alt_rounded,
                            size: 38,
                            color: _goOutsBlue,
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No selfie captured yet',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 14),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isPickingSelfie ? null : _pickSelfie,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _goOutsBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isPickingSelfie
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _isSelfieComplete
                                  ? Icons.verified_rounded
                                  : Icons.camera_alt_rounded,
                            ),
                      label: Text(
                        _isPickingSelfie
                            ? 'Opening Camera...'
                            : _isSelfieComplete
                                ? 'Selfie Captured'
                                : 'Capture Selfie',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  if (_showSelfieError) ...<Widget>[
                    SizedBox(height: 10),
                    AutoSizeText(
                      'Selfie is required.',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              // ── THE TERMS TICK BOX USED TO BE HERE ──────────────────────
              //
              // Moved to the sign-up screen on 8 August 2026. It was in the
              // wrong place in the journey: by the time a host reached this
              // card they had already given their phone number, received an
              // SMS code, and filled in their name, address and company
              // number. Consent asked at the end of a form is consent asked
              // after the fact.
              //
              // It is now the last thing before the phone number is submitted,
              // and Continue there is blocked until it is ticked. The
              // 'termsAccepted' field written below still records it — the
              // agreement happened, one screen earlier.
              SizedBox(height: 6),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitBusinessForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _goOutsBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : AutoSizeText(
                          'Complete Business Registration',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String upperText = newValue.text.toUpperCase();
    return TextEditingValue(
      text: upperText,
      selection: TextSelection.collapsed(offset: upperText.length),
    );
  }
}
