class BusinessValidators {
  // Postcode handling lived in DriverValidators in driver_app and was reached
  // through two forwarding methods. driver_validators.dart is gone from this
  // app — nothing about a UK postcode is driver-specific, and a host needs it
  // just as much — so the implementations moved here rather than dragging a
  // 198-line driver file along for two functions.

  /// 'sw1a1aa' -> 'SW1A 1AA'. Splits on the last three characters, which is
  /// how UK postcodes are structured regardless of outward-code length.
  static String normalizeUkPostcode(String input) {
    final String cleaned = input.trim().toUpperCase().replaceAll(
          RegExp(r'\s+'),
          '',
        );

    if (cleaned.length <= 3) {
      return cleaned;
    }

    final String outward = cleaned.substring(0, cleaned.length - 3);
    final String inward = cleaned.substring(cleaned.length - 3);
    return '$outward $inward';
  }

  static String? postcodeValidator(String? value) {
    final String postcode = normalizeUkPostcode(value ?? '');

    if (postcode.isEmpty) {
      return 'Postcode is required';
    }

    // GIR 0AA is a real postcode (Girobank) that the general pattern rejects,
    // hence the explicit alternative.
    final RegExp postcodeRegex = RegExp(
      r'^(GIR 0AA|[A-Z]{1,2}[0-9][A-Z0-9]?\s[0-9][A-Z]{2})$',
    );

    if (!postcodeRegex.hasMatch(postcode)) {
      return 'Enter a valid postcode';
    }

    return null;
  }

  static String? requiredField(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  static String? nameValidator(String? value, String label) {
    final String? required = requiredField(value, label);
    if (required != null) {
      return required;
    }

    final String cleaned = value!.trim();
    if (!RegExp(r"^[A-Za-z .'-]{2,}$").hasMatch(cleaned)) {
      return 'Enter a valid $label';
    }
    return null;
  }

  static String? emailValidator(String? value) {
    final String? required = requiredField(value, 'Email Address');
    if (required != null) {
      return required;
    }

    final String cleaned = value!.trim();
    final RegExp pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return pattern.hasMatch(cleaned) ? null : 'Enter a valid email address';
  }

  static String? confirmEmailValidator(String? value, String email) {
    final String? emailError = emailValidator(value);
    if (emailError != null) {
      return emailError;
    }

    if (value!.trim().toLowerCase() != email.trim().toLowerCase()) {
      return 'Email addresses do not match';
    }
    return null;
  }

  static String? pinValidator(String? value) {
    if (value == null || value.isEmpty) return 'PIN is required';
    if (value.length < 4) return 'PIN must be 4 digits';
    if (!RegExp(r'^\d{4}$').hasMatch(value)) return 'PIN must contain digits only';
    return null;
  }

  static String? confirmPinValidator(String? value, String pin) {
    if (value == null || value.isEmpty) return 'Please confirm your PIN';
    if (value != pin) return 'PINs do not match';
    return null;
  }

  static String? cityValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'City is required';
    }
    return null;
  }

  static String? countryValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Country is required';
    }
    return null;
  }

  static String? companyNumberValidator(String? value) {
    return requiredField(value, 'Business / Company Number');
  }
}
