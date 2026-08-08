// The one place that names the collection a Short Stay host lives in.
//
// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
//
// Until 8 August 2026 a host was written to /businesses. That was wrong, and
// it was my mistake — I wrote comments in several files asserting it was a
// deliberate design decision, sharing one record between a host and a
// driver_app Business Partner. It was not deliberate. It happened because
// host registration was copied from driver_app and the collection name came
// along with it.
//
// /businesses is the DRIVER LEAD business partner collection. Open
// driver_app/lib/features/home/business_home_screen.dart and the whole
// account is four things: My Referral Link, My Referrals, Business Profile,
// Messages. It is a referral partner who earns commission for introducing
// businesses to GoOuts. It is not a merchant — merchants are /merchants —
// and it is certainly not somebody letting a flat.
//
// ── THE TWO THINGS THAT WERE ACTUALLY BROKEN ───────────────────────────────
//
// 1. driver_app/lib/features/auth/login_screen.dart checks /businesses
//    BEFORE /drivers. A host who installed GoOuts Lead was logged straight
//    into the Business Partner referral dashboard — an account they never
//    created. Worse, a courier who also let a property would have their
//    driver login hijacked by their host record.
//
// 2. Every /businesses write generates ownReferralCode, so every host was
//    silently enrolled in the lead referral programme and counted as a lead
//    partner in referral analytics and commission maths.
//
// Neither was cosmetic and neither would have shown up as an error.
//
// ── THE SHAPE NOW ──────────────────────────────────────────────────────────
//
// One collection per ROLE, all keyed by the same Firebase uid:
//
//   /drivers        courier
//   /cab_drivers    rider
//   /food_drivers   food courier
//   /businesses     driver lead business partner
//   /merchants      cafe, restaurant, shop
//   /stay_hosts     someone letting a property        ← this file
//
// A pub with rooms is the case that proves the rule rather than breaking it:
// it gets a /merchants record for the cashback side and a /stay_hosts record
// for the rooms, under one login. Two roles, two records, one person. One
// record trying to be both is what produced the approval bug on 7 August,
// where the admin panel and the server disagreed about the same field.
library;

/// The Firestore collection holding Short Stay host accounts.
///
/// Referenced by name in exactly one other place outside this app —
/// requireVerifiedHost() in admin_panel/functions/stay_host.js. If this
/// changes, that changes.
const String kStayHostsCollection = 'stay_hosts';
