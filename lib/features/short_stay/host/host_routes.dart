import 'package:flutter/material.dart';

import 'host_01_dashboard_screen.dart';
import 'host_02_create_listing_address_screen.dart';
import 'host_03_create_listing_location_confirm_screen.dart';
import 'host_04_create_listing_property_details_screen.dart';
import 'host_05_create_listing_amenities_screen.dart';
import 'host_06_create_listing_photos_screen.dart';
import 'host_07_create_listing_pricing_screen.dart';
import 'host_08_create_listing_legal_screen.dart';
import 'host_09_payout_details_screen.dart';
import 'host_10_my_listings_screen.dart';
import 'host_11_listing_preview_screen.dart';
import 'host_12_availability_calendar_screen.dart';
import 'host_13_booking_requests_screen.dart';
import 'host_14_pricing_alert_screen.dart';
import 'host_15_booking_details_screen.dart';
import 'host_16_pre_arrival_capture_screen.dart';
import 'host_17_make_claim_screen.dart';
import 'host_18_claim_status_screen.dart';
import 'host_19_claim_details_screen.dart';
import 'host_20_earnings_screen.dart';
import 'host_21_help_centre_screen.dart';
import 'host_22_guest_messaging_screen.dart';
import 'host_23_notification_settings_screen.dart';
import 'host_24_profile_screen.dart';
import 'host_25_property_analytics_screen.dart';
import '../../support/host_support_screens.dart';
import '../../auth/host_change_pin_screen.dart';
import '../../support/host_contact_support_screen.dart';
import '../../support/host_message_center_screen.dart';
import 'host_25_settings_screen.dart';
import 'host_26_notifications_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Short Stay HOST routing.
//
// Same shape as StayRoutes for the guest side, and for the same reason:
// main.dart already carries around 60 named routes and adding 25 more would
// make it the largest file in the app. main.dart gains ONE more line, chained
// after the guest resolver:
//
//     onGenerateRoute: (s) =>
//         StayRoutes.onGenerateRoute(s) ?? HostRoutes.onGenerateRoute(s),
//
// Returning null when the route is not ours is what makes chaining work.
//
// THE RULE, unchanged: PASS IDS, NEVER OBJECTS. A route argument holding a
// StayListing breaks deep links, breaks state restoration after the OS kills
// the app in the background, and is a known cause of null crashes on resume.
//
// ── EVERY SCREEN BELOW IS UNWIRED ───────────────────────────────────────────
//
// These 25 files came from Stitch on 4 August 2026. They render placeholder
// copy and every handler is empty. Routing them makes them REACHABLE, not
// FUNCTIONAL, and the two are easy to confuse when a screen looks finished.
//
// Nothing on the host side has a backend yet. In particular:
//
//   createStayListing     the 02-08 wizard writes nothing
//   acceptStayBooking     13 cannot accept a request, so a guest booking
//                         sits at 'pending' forever
//   host calendar writes  blocked_dates is `allow write: if false` for
//                         clients, deliberately — 12 needs a function
//   claims                17, 18 and 19 have no createStayClaim,
//                         contestStayClaim or decideStayClaim
//
// See SHORT_STAY_HOST_WIRING_PLAN.md part 2 for the full list.
//
// report_no_show is NOT routed. It was drawn by Stitch and deferred: a
// no-show is a non-cancellation, so the host is already paid under the terms
// snapshotted onto the booking and there is nothing for a screen to do until
// payments are live.
// ─────────────────────────────────────────────────────────────────────────────

class HostRoutes {
  HostRoutes._();

  static const dashboard      = '/host';
  static const myListings     = '/host/listings';
  static const listingPreview = '/host/listings/preview';

  // The create-listing wizard, in order. Step 4 of 4 on screen 08 is the
  // compliance gate — see the plan; it is the screen that decides whether
  // GoOuts asked a host if they were allowed to let the property.
  static const newAddress     = '/host/new/address';
  static const newLocation    = '/host/new/location';
  static const newDetails     = '/host/new/details';
  static const newAmenities   = '/host/new/amenities';
  static const newPhotos      = '/host/new/photos';
  static const newPricing     = '/host/new/pricing';
  static const newLegal       = '/host/new/legal';
  static const payoutDetails  = '/host/payout';

  static const calendar       = '/host/calendar';
  static const requests       = '/host/requests';
  static const pricingAlert   = '/host/pricing-alert';
  static const booking        = '/host/booking';
  static const preArrival     = '/host/booking/capture';

  static const makeClaim      = '/host/claim/new';
  static const claimStatus    = '/host/claim/status';
  static const claimDetails   = '/host/claim';

  static const earnings       = '/host/earnings';
  static const analytics      = '/host/analytics';
  static const messaging      = '/host/messages';
  static const help           = '/host/help';
  static const messages       = '/host/messages/support';
  static const changePin      = '/host/profile/pin';
  static const contactSupport = '/host/support/contact';
  static const messageCenter  = '/host/messages/all';
  // NAMED appSettings, NOT settings, DELIBERATELY.
  //
  // onGenerateRoute takes a parameter called `settings` (it is a
  // RouteSettings — Flutter's own name). A constant called `settings`
  // is shadowed by it inside that method, so the switch case below
  // resolved to the PARAMETER and the analyzer rejected it with
  // constant_pattern_with_non_constant_expression.
  //
  // Qualifying it as HostRoutes.settings would also compile, but the
  // next person to add a route would hit the same trap. A name that
  // cannot collide is the better fix.
  static const appSettings    = '/host/settings';
  static const notificationFeed = '/host/notifications';
  static const notifications  = '/host/settings/notifications';
  static const profile        = '/host/profile';

  /// Every route this feature owns. The guard below turns a typo into a clear
  /// error rather than a blank screen.
  static const _all = <String>{
    dashboard, myListings, listingPreview,
    newAddress, newLocation, newDetails, newAmenities, newPhotos, newPricing,
    newLegal, payoutDetails,
    calendar, requests, pricingAlert, booking, preArrival,
    makeClaim, claimStatus, claimDetails,
    earnings, analytics, messaging, help, notifications, profile,
    messages, changePin, contactSupport, messageCenter, appSettings,
    notificationFeed,
  };

  static bool owns(String? name) => name != null && _all.contains(name);

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final name = settings.name;
    if (!owns(name)) return null; // not ours — let the next resolver try

    Widget page() => switch (name) {
          dashboard      => const HostDashboardScreen(),
          myListings     => const MyListingsScreen(),
          listingPreview => const ListingPreviewScreen(),

          newAddress     => const CreateListingAddressScreen(),
          newLocation    => const CreateListingLocationConfirmScreen(),
          newDetails     => const PropertyDetailsScreen(),
          newAmenities   => const AmenitiesSelectionScreen(),
          newPhotos      => const PhotoUploadScreen(),
          newPricing     => const PricingAndRulesScreen(),
          newLegal       => const LegalComplianceScreen(),
          payoutDetails  => const PayoutDetailsScreen(),

          calendar       => const AvailabilityCalendarScreen(),
          requests       => const BookingRequestsScreen(),
          pricingAlert   => const PricingAlertScreen(),
          booking        => const HostBookingDetailsScreen(),
          preArrival     => const HostPreArrivalCaptureScreen(),

          makeClaim      => const MakeClaimScreen(),
          claimStatus    => const ClaimStatusScreen(),
          claimDetails   => const ClaimDetailsScreen(),

          earnings       => const HostEarningsScreen(),
          analytics      => const PropertyAnalyticsScreen(),
          messaging      => const GuestMessagingScreen(),
          help           => const HelpCentreScreen(),
          messages       => const HostSupportTicketsScreen(),
          changePin      => const HostChangePinScreen(),
          contactSupport => const HostContactSupportScreen(),
          messageCenter  => const HostMessageCenterScreen(),
          appSettings    => const HostSettingsScreen(),
          notificationFeed => const HostNotificationsScreen(),
          notifications  => const NotificationSettingsScreen(),
          profile        => const HostProfileScreen(),

          _              => const _HostRouteMissing(),
        };

    // The wizard steps present as a flow, not as sheets. Nothing here is a
    // modal yet; when 12's date picker becomes a sheet it goes in this list.
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => page(),
    );
  }
}

class _HostRouteMissing extends StatelessWidget {
  const _HostRouteMissing();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'That page could not be opened. Please go back and try again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
