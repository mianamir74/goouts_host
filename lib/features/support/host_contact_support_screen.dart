// Contact Support — host.
//
// Same screen as goouts_app/lib/screens/contact_support_screen.dart: same
// badge, same heading, same card, same dropdown, same "Check for Help"
// button, same reply-time line, same system status block, same bottom nav.
// Keeping every app's support entry point identical is deliberate — a host
// who also uses the consumer app should not have to learn a second layout,
// and every app files into the same admin queue.
//
// ── WHAT IS DIFFERENT, AND WHY ───────────────────────────────────────────
//
// 1. THE TOPICS. A host has no transactions, no cashback, no virtual card and
//    no food order. Reusing the consumer's seven topics would have given
//    hosts a form that cannot describe a single thing that actually happens
//    to them. All seven are replaced.
//
// 2. TWO TOPICS TELL THE TRUTH INSTEAD OF SHOWING NUMBERS. Payments are not
//    integrated and claims are not built, so "Payouts" and "Damage" return an
//    explicit not-yet state. See host_self_service_service.dart.
//
// 3. This screen requires a signed-in host, because every lookup is scoped to
//    a uid. The pre-auth sheet on login/signup stays as it is — there is no
//    account to look anything up in at that point.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../common/goouts_sheet.dart';
import '../short_stay/host/host_bottom_nav.dart';
import '../short_stay/host/host_routes.dart';
import 'host_self_service_service.dart';
import 'host_support_service.dart';

class HostContactSupportScreen extends StatefulWidget {
  const HostContactSupportScreen({super.key});

  @override
  State<HostContactSupportScreen> createState() =>
      _HostContactSupportScreenState();
}

class _HostContactSupportScreenState extends State<HostContactSupportScreen> {
  // Same three colours as the consumer screen, by value, so the two screens
  // are pixel-identical rather than merely similar.
  static const Color _primary = Color(0xFF0392CA);
  static const Color _dark = Color(0xFF0D1B3E);
  static const Color _teal = Color(0xFF0A6E8A);
  static const Color _chipBg = Color(0xFFD6EEF8);
  static const Color _fieldBg = Color(0xFFF0F6FA);

  final _service = HostSupportService();
  final _selfService = HostSelfServiceService();

  // ── Topics — HOST. Every one of these is different from the consumer. ────
  final List<Map<String, String>> _topics = <Map<String, String>>[
    {'label': '— Select a Topic —', 'value': ''},
    {'label': 'Bookings & Guests', 'value': 'booking_guest'},
    {'label': 'My Properties', 'value': 'listing_issue'},
    {'label': 'Calendar & Availability', 'value': 'calendar_availability'},
    {'label': 'Payouts & Earnings', 'value': 'payout_earnings'},
    {'label': 'Verification & Account', 'value': 'verification_account'},
    {'label': 'Damage & Evidence', 'value': 'damage_evidence'},
    {'label': 'Other', 'value': 'other'},
  ];

  // ── Sub-topics — HOST ────────────────────────────────────────────────────
  final Map<String, List<Map<String, String>>> _subTopics =
      <String, List<Map<String, String>>>{
    'booking_guest': <Map<String, String>>[
      {
        'label': 'Guest Has Not Arrived',
        'icon': 'hourglass',
        'desc': 'Check-in time has passed with no guest'
      },
      {
        'label': 'Need to Cancel a Booking',
        'icon': 'block',
        'desc': 'I cannot honour a booking I accepted'
      },
      {
        'label': 'Guest Broke House Rules',
        'icon': 'warning',
        'desc': 'Extra guests, party, smoking or pets'
      },
      {
        'label': 'Cannot Reach the Guest',
        'icon': 'no_contact',
        'desc': 'The guest is not replying to messages'
      },
      {
        'label': 'Booking Details Look Wrong',
        'icon': 'error',
        'desc': 'Dates, guest count or nights are incorrect'
      },
      {
        'label': 'Guest Wants to Change Dates',
        'icon': 'calendar',
        'desc': 'A request to move an accepted booking'
      },
      {
        'label': 'Other Booking Issue',
        'icon': 'help',
        'desc': 'Something else about a booking or guest'
      },
    ],
    'listing_issue': <Map<String, String>>[
      {
        'label': 'Listing Not Approved',
        'icon': 'cancel_doc',
        'desc': 'My property was rejected by GoOuts'
      },
      {
        'label': 'Still Waiting for Approval',
        'icon': 'hourglass',
        'desc': 'My listing has been in review a long time'
      },
      {
        'label': 'Cannot Finish My Listing',
        'icon': 'error',
        'desc': 'The create-property steps will not complete'
      },
      {
        'label': 'Photos Will Not Upload',
        'icon': 'upload',
        'desc': 'Property photos fail or disappear'
      },
      {
        'label': 'Wrong Address or Postcode',
        'icon': 'home',
        'desc': 'The address on my listing is incorrect'
      },
      {
        'label': 'Want to Remove a Property',
        'icon': 'block',
        'desc': 'I need a listing taken down'
      },
      {
        'label': 'Other Property Issue',
        'icon': 'help',
        'desc': 'Something else about my properties'
      },
    ],
    'calendar_availability': <Map<String, String>>[
      {
        'label': 'Blocked Dates Not Saving',
        'icon': 'calendar',
        'desc': 'Dates I blocked are still bookable'
      },
      {
        'label': 'Double Booking',
        'icon': 'repeat',
        'desc': 'Two bookings landed on the same nights'
      },
      {
        'label': 'Need to Block a Long Period',
        'icon': 'timer',
        'desc': 'Closing my property for a season'
      },
      {
        'label': 'Nightly Rate Is Wrong',
        'icon': 'money_off',
        'desc': 'The price shown to guests is incorrect'
      },
      {
        'label': 'Minimum Stay Not Applying',
        'icon': 'error',
        'desc': 'Guests can book fewer nights than I set'
      },
      {
        'label': 'Other Calendar Issue',
        'icon': 'help',
        'desc': 'Something else about availability'
      },
    ],
    'payout_earnings': <Map<String, String>>[
      {
        'label': 'When Will I Be Paid?',
        'icon': 'timer',
        'desc': 'Question about payout timing'
      },
      {
        'label': 'Bank Details',
        'icon': 'bank',
        'desc': 'Adding or changing where I get paid'
      },
      {
        'label': 'Commission Question',
        'icon': 'percent',
        'desc': 'What GoOuts charges on a booking'
      },
      {
        'label': 'Tax and Invoices',
        'icon': 'receipt',
        'desc': 'VAT, self-assessment or records'
      },
      {
        'label': 'Other Payout Question',
        'icon': 'help',
        'desc': 'Something else about being paid'
      },
    ],
    'verification_account': <Map<String, String>>[
      {
        'label': 'Verification Rejected',
        'icon': 'cancel_doc',
        'desc': 'My identity check was not approved'
      },
      {
        'label': 'Verification Taking Long',
        'icon': 'hourglass',
        'desc': 'I am still waiting to be verified'
      },
      {
        'label': 'Re-submit My Documents',
        'icon': 'upload',
        'desc': 'I need to send my ID again'
      },
      {
        'label': 'Cannot Sign In',
        'icon': 'lock',
        'desc': 'PIN or text code is not working'
      },
      {
        'label': 'Change My Phone Number',
        'icon': 'phone',
        'desc': 'My account is on an old number'
      },
      {
        'label': 'Business Details Wrong',
        'icon': 'store',
        'desc': 'Name, address or company number is incorrect'
      },
      {
        'label': 'Close My Host Account',
        'icon': 'block',
        'desc': 'I want to stop hosting with GoOuts'
      },
      {
        'label': 'Other Account Issue',
        'icon': 'help',
        'desc': 'Something else about my account'
      },
    ],
    'damage_evidence': <Map<String, String>>[
      {
        'label': 'Guest Damaged My Property',
        'icon': 'report',
        'desc': 'Something was broken during a stay'
      },
      {
        'label': 'Items Missing After a Stay',
        'icon': 'block',
        'desc': 'Belongings were taken from the property'
      },
      {
        'label': 'Photos Will Not Upload',
        'icon': 'upload',
        'desc': 'Evidence capture is failing'
      },
      {
        'label': 'Extra Cleaning Needed',
        'icon': 'warning',
        'desc': 'The property was left in a poor state'
      },
      {
        'label': 'Other Damage Issue',
        'icon': 'help',
        'desc': 'Something else about damage or evidence'
      },
    ],
  };

  static const Map<String, IconData> _iconMap = <String, IconData>{
    'error': Icons.error_outline_rounded,
    'repeat': Icons.repeat_rounded,
    'block': Icons.block_rounded,
    'money_off': Icons.money_off_rounded,
    'hourglass': Icons.hourglass_bottom_rounded,
    'help': Icons.help_outline_rounded,
    'warning': Icons.warning_amber_rounded,
    'lock': Icons.lock_outline_rounded,
    'timer': Icons.timer_outlined,
    'store': Icons.store_rounded,
    'cancel_doc': Icons.cancel_presentation_rounded,
    'home': Icons.home_outlined,
    'upload': Icons.upload_rounded,
    'calendar': Icons.calendar_month_rounded,
    'no_contact': Icons.speaker_notes_off_rounded,
    'report': Icons.report_problem_rounded,
    'bank': Icons.account_balance_rounded,
    'percent': Icons.percent_rounded,
    'receipt': Icons.receipt_long_rounded,
    'phone': Icons.phone_iphone_rounded,
  };

  // ── State ────────────────────────────────────────────────────────────────
  String _selectedTopicValue = '';
  String _selectedTopicLabel = '— Select a Topic —';
  String? _selectedSubTopic;
  Map<String, dynamic> _lastSelfServiceData = <String, dynamic>{};

  bool _submitting = false;
  bool _loadingCheck = false;
  String? _errorMsg;

  // ── Check for Help ───────────────────────────────────────────────────────
  Future<void> _checkBeforeSubmit() async {
    if (_selectedTopicValue.isEmpty) {
      setState(() => _errorMsg = 'Please select a topic.');
      return;
    }
    if (_subTopics.containsKey(_selectedTopicValue) &&
        _selectedSubTopic == null) {
      setState(() => _errorMsg = 'Please select a related issue type.');
      return;
    }

    setState(() {
      _loadingCheck = true;
      _errorMsg = null;
    });

    final data = await _selfService.fetchForTopic(_selectedTopicValue);
    if (!mounted) return;
    setState(() {
      _loadingCheck = false;
      _lastSelfServiceData = data;
    });

    // "Other" has nothing to look up, and a sheet that says "we found nothing"
    // is worse than going straight to the form.
    if (_selectedTopicValue == 'other' || data.isEmpty) {
      _showEscalationSheet();
      return;
    }
    _showSelfServiceSheet(data);
  }

  // ── Submit ───────────────────────────────────────────────────────────────
  Future<void> _submit({String message = ''}) async {
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    // Context snapshot for the admin panel. Only plain values — anything the
    // reviewer would otherwise have to go and look up by hand.
    final snapshot = <String, dynamic>{};
    final d = _lastSelfServiceData;
    if (d['kycStatus'] != null) snapshot['kycStatus'] = d['kycStatus'];
    if (d['kycLabel'] != null) snapshot['kycLabel'] = d['kycLabel'];
    if (d['businessName'] != null && '${d['businessName']}'.isNotEmpty) {
      snapshot['businessName'] = d['businessName'];
    }
    if (d['live'] != null) snapshot['liveListings'] = d['live'];
    if (d['draft'] != null) snapshot['draftListings'] = d['draft'];
    if (d['pending'] != null) snapshot['pendingBookings'] = d['pending'];
    if (d['confirmed'] != null) snapshot['confirmedBookings'] = d['confirmed'];

    final bookings = (d['bookings'] ?? const <Map<String, dynamic>>[]) as List;
    if (bookings.isNotEmpty) {
      snapshot['recentBookings'] = bookings
          .take(3)
          .map((b) => <String, dynamic>{
                'ref': b['ref'] ?? '',
                'status': b['status'] ?? '',
                'checkIn': b['checkIn'] ?? '',
                'checkOut': b['checkOut'] ?? '',
              })
          .toList();
    }
    final listings = (d['listings'] ?? const <Map<String, dynamic>>[]) as List;
    if (listings.isNotEmpty) {
      snapshot['properties'] = listings
          .take(3)
          .map((l) => <String, dynamic>{
                'title': l['title'] ?? '',
                'status': l['status'] ?? '',
              })
          .toList();
    }

    try {
      final result = await _service.submitTicket(
        category: _selectedTopicValue,
        categoryLabel: _selectedTopicLabel,
        subject: _selectedSubTopic ?? _selectedTopicLabel,
        message: message,
        subTopic: _selectedSubTopic ?? '',
        contextSnapshot: snapshot,
      );
      if (!mounted) return;
      _showSuccess(
        ticketNumber: result['ticketNumber'] ?? '',
        subject: _selectedSubTopic ?? _selectedTopicLabel,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMsg = 'Something went wrong. Please try again.';
      });
    }
  }

  void _showSuccess({required String ticketNumber, required String subject}) {
    setState(() {
      _submitting = false;
      _selectedTopicValue = '';
      _selectedTopicLabel = '— Select a Topic —';
      _selectedSubTopic = null;
      _lastSelfServiceData = <String, dynamic>{};
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 22),
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFF388E3C), size: 32),
            ),
            const SizedBox(height: 16),
            Text('Ticket submitted',
                style: GoogleFonts.inter(
                    fontSize: 19, fontWeight: FontWeight.w800, color: _dark)),
            const SizedBox(height: 8),
            Text(
              ticketNumber.isEmpty
                  ? 'Our team will get back to you shortly.'
                  : 'Reference $ticketNumber. Our team usually replies '
                      'within 2 hours.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(subject,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500])),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context)
                      .pushNamed(HostRoutes.messageCenter, arguments: 1);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('View my messages',
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close',
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600])),
            ),
          ],
        ),
      ),
    );
  }

  // ── Self-service sheet ───────────────────────────────────────────────────
  void _showSelfServiceSheet(Map<String, dynamic> data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx2, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          color: _chipBg,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.search_rounded,
                          color: _primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('We found this for you',
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _dark)),
                          Text('Check if this resolves your issue',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 24, color: Colors.grey[100]),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: <Widget>[
                    _selfServiceContent(data),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx2);
                          GoOutsSheet.success(
                            context,
                            title: 'All good',
                            message: 'Glad we could help.',
                          );
                        },
                        icon: const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 18),
                        label: Text('This solved my issue',
                            style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF388E3C),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx2);
                          _showEscalationSheet();
                        },
                        icon: Icon(Icons.send_rounded,
                            color: Colors.grey[600], size: 16),
                        label: Text('Still need help — Submit Ticket',
                            style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700])),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── What the self-service sheet actually shows ───────────────────────────
  Widget _selfServiceContent(Map<String, dynamic> data) {
    if (data['signedOut'] == true) {
      return _infoTile(Icons.lock_outline_rounded, Colors.orange,
          'You are signed out', 'Please sign in again and retry.');
    }
    if (data['error'] != null) {
      return _infoTile(
          Icons.wifi_off_rounded,
          Colors.orange,
          'We could not check your account',
          'Submit a ticket below and our team will look it up for you.');
    }

    return switch (_selectedTopicValue) {
      'booking_guest' => _bookingsView(data),
      'listing_issue' || 'calendar_availability' => _listingsView(data),
      'payout_earnings' => _payoutsView(data),
      'verification_account' => _verificationView(data),
      'damage_evidence' => _evidenceView(data),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _bookingsView(Map<String, dynamic> data) {
    final bookings =
        (data['bookings'] ?? const <Map<String, dynamic>>[]) as List;
    if (bookings.isEmpty) {
      return _infoTile(
          Icons.event_busy_rounded,
          Colors.blueGrey,
          'No bookings yet',
          'Nothing has been booked at your properties so far. If you were '
              'expecting a booking to appear here, tell us below.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _countRow(<List<dynamic>>[
          <dynamic>['Awaiting your reply', data['pending'], Colors.orange],
          <dynamic>['Confirmed', data['confirmed'], const Color(0xFF388E3C)],
          <dynamic>['Cancelled', data['cancelled'], Colors.grey],
        ]),
        const SizedBox(height: 16),
        Text('YOUR RECENT BOOKINGS',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[400],
                letterSpacing: 0.8)),
        const SizedBox(height: 10),
        ...bookings.take(5).map((b) => _recordRow(
              title: '${b['checkIn']} → ${b['checkOut']}',
              sub: '${b['ref']}'
                  '${b['nights'] != null ? ' · ${b['nights']} nights' : ''}',
              status: '${b['status']}',
            )),
        const SizedBox(height: 14),
        _infoTile(
            Icons.info_outline_rounded,
            _primary,
            'Awaiting your reply?',
            'A booking sits as pending until you accept or decline it in '
                'Bookings. Guests are not charged before you accept.'),
      ],
    );
  }

  Widget _listingsView(Map<String, dynamic> data) {
    final listings =
        (data['listings'] ?? const <Map<String, dynamic>>[]) as List;
    if (listings.isEmpty) {
      return _infoTile(
          Icons.home_work_outlined,
          Colors.blueGrey,
          'You have no properties yet',
          'Add a property from your dashboard. It stays a draft until GoOuts '
              'has checked it.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _countRow(<List<dynamic>>[
          <dynamic>['Live', data['live'], const Color(0xFF388E3C)],
          <dynamic>['In review', data['draft'], Colors.orange],
          <dynamic>['Not approved', data['rejected'], Colors.red],
        ]),
        const SizedBox(height: 16),
        Text('YOUR PROPERTIES',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey[400],
                letterSpacing: 0.8)),
        const SizedBox(height: 10),
        ...listings.take(5).map((l) => _recordRow(
              title: '${l['title']}',
              sub: '${l['town']}',
              status: '${l['status']}',
            )),
        const SizedBox(height: 14),
        _infoTile(
            Icons.info_outline_rounded,
            _primary,
            'Why is my property not live?',
            'Every new listing is checked by GoOuts before guests can see it. '
                'A property in review is normal and needs nothing from you.'),
        if (_selectedTopicValue == 'calendar_availability') ...<Widget>[
          const SizedBox(height: 10),
          _infoTile(
              Icons.calendar_month_rounded,
              _primary,
              'Blocking dates',
              'Open a property, then Availability, and tap the nights to '
                  'block. Blocked nights stop new bookings but do not cancel '
                  'ones you have already accepted.'),
        ],
      ],
    );
  }

  // NOTE: no figures. Payments are not integrated. Do not add a balance here.
  Widget _payoutsView(Map<String, dynamic> data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _infoTile(
              Icons.schedule_rounded,
              Colors.orange,
              'Payouts are not switched on yet',
              'GoOuts is not taking guest payments yet, so there is nothing '
                  'to pay out and no balance to show. You can list, take '
                  'bookings and message guests in the meantime.'),
          const SizedBox(height: 10),
          _infoTile(Icons.account_balance_rounded, _primary,
              'What will happen', '${data['payoutPolicy']}'),
          const SizedBox(height: 10),
          _infoTile(
              Icons.receipt_long_rounded,
              _primary,
              'Tax',
              'Income from hosting is yours to declare. GoOuts is not your '
                  'accountant, and we will tell you in advance of any '
                  'reporting we are required to do.'),
        ],
      );

  Widget _verificationView(Map<String, dynamic> data) {
    final approved = data['kycApproved'] == true;
    final rejected = data['kycRejected'] == true;

    final (Color tone, IconData icon, String title, String body) = switch (
        (approved, rejected)) {
      (true, _) => (
          const Color(0xFF388E3C),
          Icons.verified_user_rounded,
          'You are verified',
          'Your properties can go live and guests can book them.',
        ),
      (_, true) => (
          Colors.red,
          Icons.gpp_bad_outlined,
          'Your identity check was not approved',
          'We could not verify you from what was submitted. Submit a ticket '
              'below and we will tell you exactly what is needed.',
        ),
      _ => (
          Colors.orange,
          Icons.hourglass_top_rounded,
          'Verification in progress',
          'You can add a property and prepare your listing now. GoOuts must '
              'verify you before guests can see it.',
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _infoTile(icon, tone, title, body),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _fieldBg, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: <Widget>[
              _kv('Status', '${data['kycLabel']}'),
              if ('${data['businessName']}'.isNotEmpty)
                _kv('Business', '${data['businessName']}'),
              _kv('Account', data['accountActive'] == true ? 'Active' : 'Paused'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _infoTile(
            Icons.lock_reset_rounded,
            _primary,
            'Sign-in trouble?',
            'You can change your PIN from Profile → Security. If you cannot '
                'get in at all, submit a ticket and we will help.'),
      ],
    );
  }

  // NOTE: claims do not exist yet. Do not offer to open one.
  Widget _evidenceView(Map<String, dynamic> data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _infoTile(
              Icons.photo_camera_outlined,
              _primary,
              'Your photos are being kept',
              'The before and after photos you capture for a stay are stored '
                  'against that booking. They are what any future claim would '
                  'be judged on, so keep taking them.'),
          const SizedBox(height: 10),
          _infoTile(
              Icons.schedule_rounded,
              Colors.orange,
              'Claims are not open yet',
              'Claims arrive with guest payments, because a claim needs a '
                  'deposit to be made against. Until then, report damage here '
                  'and our team will deal with it directly.'),
          // `data['confirmed'] as int` would throw on null — (null ?? 0) is
          // int passes the guard but the cast then runs on the ORIGINAL
          // null, not on the 0. Read it once into a typed local instead.
          if ((data['confirmed'] as int? ?? 0) > 0) ...<Widget>[
            const SizedBox(height: 10),
            _infoTile(Icons.event_available_rounded, _primary, 'Your stays',
                'You have ${data['confirmed']} confirmed booking(s) on record.'),
          ],
        ],
      );

  // ── Escalation sheet ─────────────────────────────────────────────────────
  void _showEscalationSheet() {
    final msgCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: _chipBg,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.support_agent_rounded,
                        color: _primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Submit a ticket',
                            style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _dark)),
                        Text('Our team will respond within 2 hours',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _fieldBg, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _kv('Topic', _selectedTopicLabel),
                    if (_selectedSubTopic != null)
                      _kv('Issue', _selectedSubTopic!),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Describe your issue',
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600])),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                    color: _fieldBg, borderRadius: BorderRadius.circular(10)),
                child: TextField(
                  controller: msgCtrl,
                  maxLines: 5,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 14, color: _dark),
                  decoration: InputDecoration(
                    hintText: 'Please describe the problem in detail...',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 14, color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting
                      ? null
                      : () {
                          if (msgCtrl.text.trim().isEmpty) {
                            GoOutsSheet.warning(
                              context,
                              title: 'Message required',
                              message: 'Please describe your issue.',
                            );
                            return;
                          }
                          final text = msgCtrl.text.trim();
                          Navigator.pop(context);
                          _submit(message: text);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Submit ticket',
                      style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Small pieces ─────────────────────────────────────────────────────────
  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: <Widget>[
            Text('$k: ',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500])),
            Expanded(
              child: Text(v,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _dark)),
            ),
          ],
        ),
      );

  Widget _infoTile(IconData icon, Color color, String title, String body) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: color, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _dark)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: Colors.grey[700],
                          height: 1.45)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _countRow(List<List<dynamic>> cells) => Row(
        children: cells.map((c) {
          final label = c[0] as String;
          final value = c[1];
          final color = c[2] as Color;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: <Widget>[
                  Text('${value ?? 0}',
                      style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _dark)),
                  const SizedBox(height: 2),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }).toList(),
      );

  Widget _recordRow(
          {required String title,
          required String sub,
          required String status}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _dark)),
                  if (sub.trim().isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 11.5, color: Colors.grey[500])),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColour(status).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_statusLabel(status),
                  style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _statusColour(status))),
            ),
          ],
        ),
      );

  static Color _statusColour(String s) => switch (s) {
        'live' || 'confirmed' => const Color(0xFF388E3C),
        'draft' || 'pending' => Colors.orange,
        'rejected' || 'declined' || 'cancelled' => Colors.red,
        _ => Colors.grey,
      };

  static String _statusLabel(String s) => switch (s) {
        'live' => 'LIVE',
        'draft' => 'IN REVIEW',
        'rejected' => 'NOT APPROVED',
        'pending' => 'AWAITING YOU',
        'confirmed' => 'CONFIRMED',
        'declined' => 'DECLINED',
        'cancelled' => 'CANCELLED',
        _ => s.toUpperCase(),
      };

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final subs = _subTopics[_selectedTopicValue];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _primary, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Contact Support',
            style: GoogleFonts.inter(
                fontSize: 18, fontWeight: FontWeight.w700, color: _primary)),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'My messages',
            icon: const Icon(Icons.history_rounded,
                color: Colors.black87, size: 22),
            onPressed: () =>
                Navigator.of(context)
                    .pushNamed(HostRoutes.messageCenter, arguments: 1),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 4),

            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _chipBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.bolt_rounded, color: _teal, size: 14),
                  const SizedBox(width: 5),
                  Text('Active Support Team',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _teal)),
                ],
              ),
            ),

            const SizedBox(height: 14),

            Text('How can we help you today?',
                style: GoogleFonts.inter(
                    fontSize: 24, fontWeight: FontWeight.w800, color: _dark)),
            const SizedBox(height: 8),
            Text(
              'Fill out the form below and our team will get back to you shortly.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.grey[500], height: 1.5),
            ),

            const SizedBox(height: 20),

            // Form card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _fieldLabel('Topic'),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: _fieldBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTopicValue,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: Colors.grey),
                        style: GoogleFonts.inter(fontSize: 14, color: _dark),
                        onChanged: (v) {
                          if (v == null) return;
                          final t =
                              _topics.firstWhere((t) => t['value'] == v);
                          setState(() {
                            _selectedTopicValue = v;
                            _selectedTopicLabel = t['label']!;
                            _selectedSubTopic = null;
                            _errorMsg = null;
                          });
                        },
                        items: _topics
                            .map((t) => DropdownMenuItem<String>(
                                  value: t['value'],
                                  child: Text(t['label']!,
                                      style: GoogleFonts.inter(
                                          fontSize: 14, color: _dark)),
                                ))
                            .toList(),
                      ),
                    ),
                  ),

                  if (subs != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                            child:
                                _fieldLabel('What is the specific issue?')),
                        if (_selectedSubTopic != null)
                          GestureDetector(
                            onTap: () =>
                                setState(() => _selectedSubTopic = null),
                            child: Text('Change',
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _primary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...subs.map((sub) {
                      final isSelected = _selectedSubTopic == sub['label'];
                      if (_selectedSubTopic != null && !isSelected) {
                        return const SizedBox.shrink();
                      }
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedSubTopic = sub['label'];
                          _errorMsg = null;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _chipBg
                                : const Color(0xFFF8FAFB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  isSelected ? _primary : Colors.grey[200]!,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _primary.withValues(alpha: 0.15)
                                      : Colors.grey[100],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _iconMap[sub['icon']] ??
                                      Icons.help_outline_rounded,
                                  color: isSelected
                                      ? _primary
                                      : Colors.grey[500],
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(sub['label']!,
                                        style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? _primary
                                                : _dark)),
                                    Text(sub['desc']!,
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: Colors.grey[500])),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded,
                                    color: _primary, size: 20),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.info_outline_rounded,
                            color: _primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Tap "Check for Help" — we will look at your own '
                              'account first and try to answer it straight away.',
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: _dark, height: 1.4)),
                        ),
                      ],
                    ),
                  ),

                  if (_errorMsg != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.red, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_errorMsg!,
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: Colors.red)),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (_submitting || _loadingCheck)
                          ? null
                          : _checkBeforeSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: (_submitting || _loadingCheck)
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Text('Check for Help',
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.access_time_rounded,
                          size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 5),
                      Text('Our team usually replies within 2 hours',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: Colors.grey[400])),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // System status. Wording differs from the consumer's "Core banking
            // and wallet services" — a host has neither.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('SYSTEM STATUS',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[400],
                          letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text('All Systems Operational',
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _dark)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Listings, bookings and messaging are running smoothly.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: Colors.grey[500], height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.profile),
    );
  }

  Widget _fieldLabel(String label) => Text(label,
      style: GoogleFonts.inter(
          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[600]));
}
