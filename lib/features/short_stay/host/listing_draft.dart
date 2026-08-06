import 'package:cloud_functions/cloud_functions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The in-progress listing, carried across the 02-08 wizard.
//
// WHY A HOLDER AND NOT ROUTE ARGUMENTS
// The wizard is eight screens. Passing the accumulated answers forward through
// eight pushNamed calls means every screen has to receive, copy and forward
// state it does not care about, and forgetting one silently drops whatever the
// host typed on the screen before it.
//
// ⚠ THIS IS IN MEMORY ONLY, AND THAT IS A KNOWN LIMITATION.
// If iOS kills the app mid-wizard — and it has killed this app for memory
// before — the host loses everything they typed and starts again. For an
// audience described in our own brief as "time poor, often older and less
// confident with apps", that is a real cost.
//
// It is NOT fixed here because the fix is a decision, not a line of code:
// either persist to local storage, or create the Firestore draft at step 1 and
// update it per step. The second is better but createStayListing requires the
// compliance answers from step 7, so it needs splitting first.
//
// Recorded rather than quietly accepted.
// ─────────────────────────────────────────────────────────────────────────────

class ListingDraft {
  ListingDraft._();
  static final ListingDraft instance = ListingDraft._();

  // 02 address
  String line1 = '';
  String town = '';
  String postcode = '';

  // 04 property details
  String title = '';
  String description = '';
  String propertyType = 'flat';
  int bedrooms = 1;
  int beds = 1;
  int bathrooms = 1;
  int maxGuests = 2;

  // 05 amenities
  List<String> amenities = [];

  // 06 photos — URLs only. The upload to Storage happens on that screen; this
  // carries the result, never the bytes.
  List<Map<String, String>> photos = [];

  // 07 pricing
  int nightlyRatePence = 0;
  int cleaningFeePence = 0;
  String cancellationPolicy = 'moderate';
  String bookingMode = 'request';

  // 08 legal. All three must be true or the server refuses.
  bool mortgagePermit = false;
  bool safetyDuty = false;
  bool nightLimitAwareness = false;
  String registrationNumber = '';

  /// Cleared when the wizard is left or a listing is submitted, so a second
  /// listing does not inherit the first one's answers. Easy to forget, and the
  /// symptom is a host's new property arriving with the old one's amenities.
  void reset() {
    line1 = town = postcode = '';
    title = description = '';
    propertyType = 'flat';
    bedrooms = beds = bathrooms = 1;
    maxGuests = 2;
    amenities = [];
    photos = [];
    nightlyRatePence = cleaningFeePence = 0;
    cancellationPolicy = 'moderate';
    bookingMode = 'request';
    mortgagePermit = safetyDuty = nightLimitAwareness = false;
    registrationNumber = '';
  }

  bool get addressComplete =>
      line1.trim().isNotEmpty &&
      town.trim().isNotEmpty &&
      postcode.trim().isNotEmpty;

  bool get complianceComplete =>
      mortgagePermit && safetyDuty && nightLimitAwareness;

  /// Creates the listing. Returns its id.
  ///
  /// The server decides three things this client never sends:
  ///   status        always 'draft' — only an admin makes a listing live
  ///   captureRooms  generated from bedrooms and bathrooms. A host who could
  ///                 shorten it could leave out the room they intend to claim
  ///                 for
  ///   compliance.confirmedAt  a SERVER timestamp, because a device clock is
  ///                 set by the person making the legal statement
  Future<String> submit() async {
    final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('createStayListing')
        .call<Map<String, dynamic>>({
      'title': title,
      'description': description,
      'propertyType': propertyType,
      'line1': line1,
      'town': town,
      'postcode': postcode,
      'bedrooms': bedrooms,
      'beds': beds,
      'bathrooms': bathrooms,
      'maxGuests': maxGuests,
      'amenities': amenities,
      'photos': photos,
      'nightlyRate': nightlyRatePence,
      'cleaningFee': cleaningFeePence,
      'cancellationPolicy': cancellationPolicy,
      'bookingMode': bookingMode,
      'registrationNumber': registrationNumber,
      'compliance': {
        'mortgagePermit': mortgagePermit,
        'safetyDuty': safetyDuty,
        'nightLimitAwareness': nightLimitAwareness,
      },
    });
    final id = (res.data['listingId'] ?? '') as String;
    if (id.isNotEmpty) reset();
    return id;
  }
}
