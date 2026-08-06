import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

/// Shows T&C as a draggable bottom sheet — use this everywhere instead of
/// pushing TermsAndConditionsScreen as a full screen.
void showTermsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: AutoSizeText(
                      'Terms & Conditions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C1C1C),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.black54, size: 24),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                child: const _TermsContent(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _NoticePoint extends StatelessWidget {
  const _NoticePoint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AutoSizeText(
            '✓  ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF59E0B),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF78350F),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Terms & Conditions screen.
///
/// Content is hardcoded for now and will be made editable from the
/// admin panel in a future release.
class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: AutoSizeText(
          'Terms & Conditions',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: _TermsContent(),
      ),
    );
  }
}

class _TermsContent extends StatelessWidget {
  const _TermsContent();

  static const Color _goOutsBlue = Color(0xFF0392CA);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _lastUpdated('May 2026'),
        const SizedBox(height: 16),

        // ── Important Notice ─────────────────────────────────────────────
        _importantNotice(),
        const SizedBox(height: 8),

        // ── 1. Acceptance ────────────────────────────────────────────────
        _sectionTitle('1. Acceptance of Terms'),
        _body(
          'By registering for and using the GoOuts Lead Generation app ("the App"), you agree '
          'to be bound by these Terms and Conditions ("Terms"). Please read '
          'them carefully before using the App. If you do not agree to these '
          'Terms, you must not use the App.',
        ),

        // ── 2. About the App ─────────────────────────────────────────────
        _sectionTitle('2. About the App'),
        _body(
          'GoOuts Host lets property owners and managers in the United Kingdom '
          'and Northern Ireland list short-stay accommodation to guests on the '
          'GoOuts platform. GoOuts is the platform, not the accommodation '
          'provider — the agreement to stay is between you and your guest.',
        ),
        _bullet('You must be 18 years of age or older to register.'),
        _bullet(
          'You are responsible for keeping your account credentials secure '
          'and confidential.',
        ),
        _bullet(
          'You agree not to use the App for any unlawful, fraudulent, or '
          'abusive purpose.',
        ),
        _bullet(
          'One account per person is permitted. Creating multiple accounts '
          'to circumvent any restrictions is prohibited.',
        ),

        // ── 3. Photo & Document Verification ─────────────────────────────
        _sectionTitle('3. Photo and Document Verification'),
        _body(
          'To protect all users and maintain the integrity of the GoOuts '
          'platform, we collect the following during registration:',
        ),
        _subTitle('Selfie Photograph'),
        _body(
          'Your selfie is taken purely to verify your identity and confirm '
          'it matches the identity documents you submit. It is stored '
          'securely on our servers and is only accessed by authorised GoOuts '
          'staff for the sole purpose of identity verification. Your selfie '
          'is never used for marketing, advertising, or shared with any '
          'third party without your explicit consent.',
        ),
        _subTitle('Identity Documents (Passport / Driving Licence)'),
        _body(
          'We collect copies of your identity documents to verify your '
          'right to work and to confirm your identity. This is a standard '
          'compliance requirement. These documents are stored using industry-'
          'standard encryption and are accessed only by authorised staff '
          'during the verification process. We do not share your documents '
          'with any third party except where required by law.',
        ),
        _subTitle('Profile Photograph'),
        _body(
          'Your profile photo is displayed within the App to identify you to '
          'business partners. It is not used for any other purpose.',
        ),
        _body(
          'We do not sell, rent, or share your photographs or documents with '
          'advertisers or data brokers under any circumstances. All images '
          'are collected for fraud prevention and verification only.',
        ),

        // ── 4. GDPR ──────────────────────────────────────────────────────
        _sectionTitle('4. Data Protection & GDPR'),
        _body(
          'GoOuts is committed to protecting your personal data in accordance '
          'with the UK General Data Protection Regulation (UK GDPR) and the '
          'Data Protection Act 2018.',
        ),
        _subTitle('Data Controller'),
        _body(
          'GoOuts Worldwide Ltd is the data controller responsible for your personal '
          'data collected through this App.',
        ),
        _subTitle('What Data We Collect'),
        _bullet('Full name, date of birth, and contact details.'),
        _bullet('Mobile phone number for authentication purposes.'),
        _bullet('Home or business address.'),
        _bullet('Identity documents and photographs (as described above).'),
        _bullet('Property address and listing details.'),
        _bullet(
          'Usage data and technical information to improve the App.',
        ),
        _subTitle('Lawful Basis for Processing'),
        _bullet(
          'Contractual necessity — to provide and manage your account and '
          'our services.',
        ),
        _bullet(
          'Legitimate interests — fraud prevention, platform security, and '
          'identity verification.',
        ),
        _bullet(
          'Legal obligation — to comply with applicable UK law and '
          'regulatory requirements.',
        ),
        _bullet(
          'Consent — where you have explicitly agreed to optional data '
          'processing.',
        ),
        _subTitle('Your Rights Under UK GDPR'),
        _body('You have the right to:'),
        _bullet('Access the personal data we hold about you.'),
        _bullet('Request correction of inaccurate or incomplete data.'),
        _bullet(
          'Request erasure of your data ("right to be forgotten"), where '
          'applicable.',
        ),
        _bullet(
          'Restrict or object to certain processing of your data.',
        ),
        _bullet(
          'Data portability — receive your data in a structured, '
          'machine-readable format.',
        ),
        _bullet(
          'Withdraw consent at any time, where processing is based on '
          'consent.',
        ),
        _body(
          'To exercise any of these rights, please contact us at '
          'privacy@goouts.app. We will respond within 30 days.',
        ),
        _subTitle('Data Retention'),
        _body(
          'Your personal data is retained for as long as your account '
          'remains active, or as long as necessary to fulfil our legal '
          'obligations. When your account is closed, data is securely '
          'deleted within 90 days unless a longer retention period is '
          'required by law.',
        ),
        _subTitle('Third-Party Service Providers'),
        _body(
          'We use trusted third-party providers (including Firebase by '
          'Google, Mapbox, and Ordnance Survey) to operate the App. These '
          'providers are contractually obliged to protect your data and '
          'may only process it on our instructions. Where data is '
          'transferred outside the UK, appropriate safeguards are in '
          'place in accordance with UK GDPR.',
        ),
        _subTitle('Data Security'),
        _body(
          'We implement appropriate technical and organisational measures '
          'to protect your personal data against unauthorised access, '
          'disclosure, alteration, or destruction. However, no system is '
          'completely infallible, and we encourage you to keep your login '
          'credentials secure.',
        ),

        // ── 5. User Responsibilities ──────────────────────────────────────
        _sectionTitle('5. User Responsibilities'),
        _body('By using the App, you agree to:'),
        _bullet(
          'Provide accurate, complete, and up-to-date information at all '
          'times.',
        ),
        _bullet(
          'Not impersonate any other person or misrepresent your identity.',
        ),
        _bullet(
          'Not upload false, forged, or misleading documents.',
        ),
        _bullet(
          'Comply with all applicable UK laws and regulations while '
          'using the App.',
        ),
        _bullet(
          'Report any suspicious activity, security concerns, or '
          'suspected fraud to GoOuts immediately.',
        ),

        // ── 6. Suspension & Termination ───────────────────────────────────
        _sectionTitle('6. Account Suspension and Termination'),
        _body(
          'GoOuts reserves the right to suspend or permanently terminate '
          'your account without prior notice if:',
        ),
        _bullet('You breach any provision of these Terms.'),
        _bullet(
          'We reasonably suspect fraudulent activity, misuse of the '
          'platform, or submission of false information.',
        ),
        _bullet(
          'You fail our identity or right-to-work verification checks.',
        ),
        _bullet(
          'You engage in behaviour that is harmful to other users, '
          'business partners, or GoOuts.',
        ),

        // ── 7. Limitation of Liability ────────────────────────────────────
        _sectionTitle('7. Limitation of Liability'),
        _body(
          'To the fullest extent permitted by applicable law, GoOuts shall '
          'not be liable for any indirect, incidental, special, or '
          'consequential loss or damage arising from your use of, or '
          'inability to use, the App. Nothing in these Terms excludes or '
          'limits our liability for death or personal injury caused by '
          'our negligence, or for fraud or fraudulent misrepresentation.',
        ),

        // ── 8. Changes to Terms ───────────────────────────────────────────
        _sectionTitle('8. Changes to These Terms'),
        _body(
          'We reserve the right to update or modify these Terms at any '
          'time. Where changes are material, we will notify you via the '
          'App or by email. Continued use of the App after notification '
          'of changes constitutes your acceptance of the updated Terms.',
        ),

        // ── 9. Governing Law ─────────────────────────────────────────────
        _sectionTitle('9. Governing Law'),
        _body(
          'These Terms are governed by and construed in accordance with '
          'the laws of England and Wales. Any disputes shall be subject '
          'to the exclusive jurisdiction of the courts of England and '
          'Wales.',
        ),

        // ── 10. Contact ───────────────────────────────────────────────────
        _sectionTitle('10. Contact Us'),
        _body(
          'If you have any questions about these Terms or our data '
          'practices, please contact us:',
        ),
        _bullet('Email: legal@goouts.app'),
        _bullet('Privacy enquiries: privacy@goouts.app'),
        _bullet('Address: GoOuts Worldwide Ltd, United Kingdom'),

      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────


  Widget _importantNotice() {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.campaign_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              SizedBox(width: 8),
              AutoSizeText(
                'Early Access — Lead Generation App',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          AutoSizeText(
            'GoOuts is currently in its pre-launch phase. This app is designed '
            'to allow property hosts to register their interest and prepare '
            'their listings ahead of our full operational launch.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF78350F),
              height: 1.55,
            ),
          ),
          SizedBox(height: 8),
          AutoSizeText(
            'It is not yet a fully operational booking platform. No live '
            'guest bookings, payments, or payouts take place within this app '
            'at this time.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF78350F),
              height: 1.55,
            ),
          ),
          SizedBox(height: 10),
          AutoSizeText(
            'What you can do right now:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF78350F),
            ),
          ),
          SizedBox(height: 6),
          _NoticePoint(
            'Register your profile and secure your place on the GoOuts platform '
            'ahead of the official launch.',
          ),
          _NoticePoint(
            'Invite friends, colleagues, and contacts to join GoOuts using your '
            'personal referral code — helping you build your network and grow '
            'your portfolio before day one.',
          ),
          _NoticePoint(
            'Track the status of everyone you have invited, see who has '
            'registered, and watch your network grow in real time.',
          ),
          _NoticePoint(
            'Be among the first to be notified when GoOuts goes live in your '
            'area and operations begin.',
          ),
          SizedBox(height: 10),
          AutoSizeText(
            'When we launch, you will be notified directly through the app and '
            'via SMS. Early registrants will receive priority access and '
            'may be eligible for launch incentives.',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Color(0xFF78350F),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lastUpdated(String date) {
    return AutoSizeText(
      'Last updated: $date',
      style: const TextStyle(
        fontSize: 12,
        color: Colors.black45,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _subTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _body(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          color: Colors.black87,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AutoSizeText(
            '• ',
            style: TextStyle(
              fontSize: 13.5,
              color: _goOutsBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.black87,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

}
