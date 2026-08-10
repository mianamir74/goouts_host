// Help centre.
//
// ── WIRED 8 August 2026. WHAT IT WAS ───────────────────────────────────────
//
// Reported as "nothing on this screen works or linked including searchbar",
// which was exactly right:
//
//   • the search field had no controller and no onChanged — you could type in
//     it and nothing filtered
//   • all seventeen help topics were `onTap: () {}`
//   • "Contact support" was `onPressed: () {}`
//   • the seventeen topic titles were single words invented by Stitch —
//     "Photos", "Pricing", "Verification" — with no article behind any of them
//
// ── THE CONTENT ALREADY EXISTED AND NOTHING READ IT ────────────────────────
//
// short_stay_host_faqs is seeded from the admin panel, has a security rule
// (`allow read: if true`), and was written specifically for hosts. The seed
// file's own comment says: "Nothing reads them until the Short Stay screens
// ship and point at them."
//
// This is that pointing. The screen now reads the collection, groups by the
// `cat` field, and expands each question in place.
//
// Field names are `cat` / `q` / `a`, NOT `category` / `question` / `answer`.
// That mismatch has already cost this project once — the FAQ seeder threw a
// null assertion because the reading code guessed the longer names.
//
// ── SEARCH IS LOCAL, ON PURPOSE ────────────────────────────────────────────
//
// It filters the documents already fetched rather than querying Firestore per
// keystroke. Firestore has no substring search, so a server-side version would
// need every prefix indexed or a third-party search service — for a few dozen
// FAQs that is a lot of machinery to answer "does this word appear".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/goouts_colors.dart';
import 'host_bottom_nav.dart';
import 'host_routes.dart';

class HelpCentreScreen extends StatefulWidget {
  const HelpCentreScreen({super.key});

  @override
  State<HelpCentreScreen> createState() => _HelpCentreScreenState();
}

class _HelpCentreScreenState extends State<HelpCentreScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// The category currently filtered to. Null shows everything.
  String? _selectedCategory;

  // ── QUICK HELP, MATCHING goouts_app's FAQ SCREEN ─────────────────────────
  //
  // ADDED 10 August 2026. goouts_app's FAQ screen opens with a 2-column grid
  // of tappable category cards under a "QUICK HELP" heading, then a
  // "FREQUENT QUESTIONS" list with a dismissable filter chip. This screen had
  // only a search box and plain category headers, so a host who did not know
  // what to search for had nothing to press.
  //
  // ⚠ THESE LABELS MUST MATCH kShortStayHostFaqCategories IN THE ADMIN PANEL
  // (admin_panel/lib/data/short_stay_faq_seed.dart). goouts_app has already
  // been bitten by exactly this: its 'Account Security' tile mapped to a
  // category name the seed never used, so tapping it always showed an empty
  // list, and nobody noticed because an empty list looks like "no articles".
  //
  // Six of the seven seeded categories are shown. 'Rules and registration' is
  // reachable through search and the full list below; a 2-column grid wants an
  // even count, and seven cards leaves a lone card on the last row.
  static const List<Map<String, dynamic>> _quickHelp = <Map<String, dynamic>>[
    {'icon': Icons.rocket_launch_outlined, 'label': 'Getting started'},
    {'icon': Icons.holiday_village_outlined, 'label': 'Your listing'},
    {'icon': Icons.calendar_month_outlined, 'label': 'Bookings'},
    {'icon': Icons.luggage_outlined, 'label': 'Arrival and departure'},
    {'icon': Icons.report_gmailerrorred_outlined, 'label': 'Damage claims'},
    {'icon': Icons.payments_outlined, 'label': 'Getting paid'},
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _quickHelpGrid() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'QUICK HELP',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GoOutsColors.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.9,
            ),
            itemCount: _quickHelp.length,
            itemBuilder: (context, i) {
              final item = _quickHelp[i];
              final label = item['label'] as String;
              final active = _selectedCategory == label;
              return GestureDetector(
                // Tapping the active card clears the filter, so the card is
                // its own off switch and a host is never stuck inside one
                // category wondering where everything else went.
                onTap: () => setState(
                    () => _selectedCategory = active ? null : label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: active ? GoOutsColors.primary : GoOutsColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: active
                            ? GoOutsColors.primary
                            : GoOutsColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white.withValues(alpha: 0.2)
                              : GoOutsColors.tint,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(item['icon'] as IconData,
                            color: active ? Colors.white : GoOutsColors.teal,
                            size: 20),
                      ),
                      const SizedBox(height: 7),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.white : GoOutsColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );

  /// "FREQUENT QUESTIONS" with the dismissable active-category chip, exactly
  /// as goouts_app does it.
  Widget _frequentHeader() => Row(
        children: <Widget>[
          Text(
            'FREQUENT QUESTIONS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GoOutsColors.onSurfaceVariant,
              letterSpacing: 1.0,
            ),
          ),
          if (_selectedCategory != null) ...<Widget>[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _selectedCategory = null),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: GoOutsColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _selectedCategory!,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: GoOutsColors.primary),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.close_rounded,
                        size: 12, color: GoOutsColors.primary),
                  ],
                ),
              ),
            ),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GoOutsColors.background,
      appBar: AppBar(
        backgroundColor: GoOutsColors.surface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GoOutsColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Help centre',
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          _searchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('short_stay_host_faqs')
                  .snapshots(),
              builder: (context, snap) {
                // Shown, never swallowed. An error rendered as "no articles"
                // sends a host to support for something the app could have
                // answered — and hides the fault from everyone.
                if (snap.hasError) {
                  return _notice(
                    'Could not load help articles.\n${snap.error}',
                    GoOutsColors.error,
                    Icons.error_outline_rounded,
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snap.data!.docs
                    .map((d) => d.data())
                    .where((m) => _str(m['q']).isNotEmpty)
                    .toList();

                if (all.isEmpty) {
                  return _notice(
                    'No help articles have been published yet. Contact '
                    'support below and someone will answer directly.',
                    GoOutsColors.onSurfaceVariant,
                    Icons.info_outline_rounded,
                  );
                }

                // Two filters, applied in order: the Quick Help category, then
                // the search text. Category first because a host who has
                // tapped a card has already narrowed their intent, and
                // searching inside that narrower set is what they expect.
                final inCategory = _selectedCategory == null
                    ? all
                    : all
                        .where((m) => _str(m['cat']) == _selectedCategory)
                        .toList();

                final matched = _query.isEmpty
                    ? inCategory
                    : inCategory.where((m) {
                        final hay =
                            '${_str(m['q'])} ${_str(m['a'])} ${_str(m['cat'])}'
                                .toLowerCase();
                        return hay.contains(_query);
                      }).toList();

                if (matched.isEmpty) {
                  // Three different empty states, because "nothing here" for
                  // three different reasons needs three different next steps.
                  // A single generic message would leave a host tapping the
                  // same card again wondering why it is broken.
                  final String msg;
                  if (_query.isNotEmpty && _selectedCategory != null) {
                    msg = 'Nothing in "$_selectedCategory" matches '
                        '"${_searchCtrl.text.trim()}". Clear the category '
                        'above to search everything.';
                  } else if (_query.isNotEmpty) {
                    msg = 'Nothing matches "${_searchCtrl.text.trim()}". Try a '
                        'different word, or contact support below.';
                  } else {
                    msg = 'No articles under "$_selectedCategory" yet. Tap the '
                        'card again to see everything, or contact support '
                        'below.';
                  }
                  return _notice(msg, GoOutsColors.onSurfaceVariant,
                      Icons.search_off_rounded);
                }

                // Grouped by category, categories in first-seen order so the
                // seed file's ordering is preserved rather than alphabetised
                // into something arbitrary.
                final groups = <String, List<Map<String, dynamic>>>{};
                for (final m in matched) {
                  final cat = _str(m['cat']).isEmpty ? 'General' : _str(m['cat']);
                  groups.putIfAbsent(cat, () => <Map<String, dynamic>>[]).add(m);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: <Widget>[
                    // Quick Help is hidden while searching. goouts_app does the
                    // same: once someone is typing, a grid of category cards is
                    // just something between them and their results.
                    if (_query.isEmpty) ...<Widget>[
                      _quickHelpGrid(),
                      const SizedBox(height: 22),
                    ],
                    _frequentHeader(),
                    const SizedBox(height: 10),
                    if (_query.isNotEmpty) ...<Widget>[
                      Text(
                        '${matched.length} '
                        '${matched.length == 1 ? "result" : "results"}',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: GoOutsColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    for (final entry in groups.entries) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                        child: Text(
                          entry.key,
                          style: GoogleFonts.inter(
                            color: GoOutsColors.navy,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: GoOutsColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: GoOutsColors.border),
                        ),
                        child: Column(
                          children: <Widget>[
                            for (int i = 0; i < entry.value.length; i++) ...[
                              _faqTile(entry.value[i],
                                  // Expanded by default when searching: after
                                  // typing a word, having to tap each result
                                  // to see whether it is the right one defeats
                                  // the search.
                                  startOpen: _query.isNotEmpty),
                              if (i != entry.value.length - 1)
                                const Divider(
                                    height: 1, color: GoOutsColors.background),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          _contactBar(),
        ],
      ),
      bottomNavigationBar: const HostBottomNav(current: HostTab.profile),
    );
  }

  static String _str(Object? v) => (v ?? '').toString().trim();

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        // THE FIX: there was no controller and no onChanged at all, so the
        // field accepted text and nothing ever read it.
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search,
              color: GoOutsColors.onSurfaceVariant),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  onPressed: () => setState(() {
                    _searchCtrl.clear();
                    _query = '';
                  }),
                ),
          hintText: 'Search help articles',
          hintStyle: GoogleFonts.inter(
              color: GoOutsColors.onSurfaceVariant, fontSize: 14),
          filled: true,
          fillColor: GoOutsColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GoOutsColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GoOutsColors.border),
          ),
        ),
      ),
    );
  }

  Widget _faqTile(Map<String, dynamic> m, {required bool startOpen}) {
    return Theme(
      // Removes the divider ExpansionTile draws by default, which would double
      // up with the one between rows.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // Rebuilt when the search changes so startOpen is re-applied. Without
        // a key that varies, Flutter reuses the old tile and keeps it shut.
        key: ValueKey('${_str(m['q'])}_$startOpen'),
        initiallyExpanded: startOpen,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _str(m['q']),
          style: GoogleFonts.inter(
            color: GoOutsColors.navy,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        children: <Widget>[
          Text(
            _str(m['a']),
            style: GoogleFonts.inter(
              color: GoOutsColors.body,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: GoOutsColors.surface,
        border: Border(top: BorderSide(color: GoOutsColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
        // Messages used to have a button here. It was the WRONG PLACE.
        //
        // A host who had been sent a message looked in Profile, found no
        // Messages row, and reported that our replies were not arriving.
        // They were — buried behind the FAQ page. Nobody opens a help
        // article to check their inbox.
        //
        // Messages now sits on the Profile, directly under Notifications,
        // exactly where goouts_app puts it. This screen keeps only what it
        // is for: answers, and a way to ask if none of them fit.
        ElevatedButton.icon(
          // Was onPressed: () {}. Opens the same sheet the sign-in screen
          // uses, which writes a real ticket to support_requests and appears
          // in the admin panel's Support section.
          //
          // accountType 'business' is what stamps the ticket so admin can tell
          // where it came from — see _sourceCollection in that sheet.
          onPressed: () =>
              Navigator.of(context).pushNamed(HostRoutes.contactSupport),
          icon: const Icon(Icons.headset_mic_outlined,
              color: Colors.white, size: 20),
          label: Text(
            'Contact support',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: GoOutsColors.teal,
            minimumSize: const Size(double.infinity, 56),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, Color colour, IconData icon) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 34, color: colour),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13.5, color: GoOutsColors.body, height: 1.5),
              ),
            ],
          ),
        ),
      );
}
