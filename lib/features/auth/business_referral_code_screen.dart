import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'business_registration_screen.dart';
import 'package:auto_size_text/auto_size_text.dart';

class BusinessReferralCodeScreen extends StatefulWidget {
  const BusinessReferralCodeScreen({
    super.key,
    this.prefilledReferralCode,
    this.inviteToken,
  });

  final String? prefilledReferralCode;
  final String? inviteToken;

  static const String defaultBusinessReferralCode = 'GB000001';

  @override
  State<BusinessReferralCodeScreen> createState() =>
      _BusinessReferralCodeScreenState();
}

class _BusinessReferralCodeScreenState
    extends State<BusinessReferralCodeScreen> {
  static const Color _goOutsBlue = Color(0xFF0392CA);

  final List<TextEditingController> _controllers =
      List<TextEditingController>.generate(
    8, // was 6
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List<FocusNode>.generate(
    8,
    (_) => FocusNode(),
  );

  // CRITICAL FIX: separate FocusNodes for the KeyboardListener wrappers.
  // A FocusNode can only be attached to one widget at a time. Previously
  // _focusNodes[index] was passed to BOTH the KeyboardListener and the
  // TextField it wraps, so the two fought over attaching the same node in
  // the focus tree — each reattach fired a notification, rebuilt, and
  // reattached again, unbounded. With 8 boxes built at once this allocated
  // multiple GB in seconds and got the app killed by iOS as out-of-memory
  // (an uncatchable kernel SIGKILL — no try/catch or timeout can stop it).
  // skipTraversal keeps these out of tab order so they never steal focus.
  final List<FocusNode> _keyEventFocusNodes = List<FocusNode>.generate(
    8,
    (_) => FocusNode(skipTraversal: true),
  );

  bool _isLoading = false;
  String? _errorText;

  bool get _hasInviteToken =>
      widget.inviteToken != null && widget.inviteToken!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final String initialCode = _buildInitialCode();
    if (initialCode.isNotEmpty) {
      _fillCode(initialCode);
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    for (final FocusNode focusNode in _focusNodes) {
      focusNode.dispose();
    }
    for (final FocusNode focusNode in _keyEventFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String _normalizeCode(String value) {
    final String cleaned = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length <= 8 ? cleaned : cleaned.substring(0, 8);
  }

  String _buildInitialCode() {
    final String prefilled = _normalizeCode(widget.prefilledReferralCode ?? '');
    if (prefilled.isNotEmpty) {
      return prefilled;
    }

    if (_hasInviteToken) {
      return BusinessReferralCodeScreen.defaultBusinessReferralCode;
    }

    return '';
  }

  void _fillCode(String code) {
    final String normalized = _normalizeCode(code);
    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].text = i < normalized.length ? normalized[i] : '';
    }
  }

  String get _typedCode =>
      _controllers.map((TextEditingController controller) => controller.text).join();

  bool get _allBoxesEmpty =>
      _controllers.every((TextEditingController controller) => controller.text.trim().isEmpty);

  bool get _allBoxesFilled =>
      _controllers.every((TextEditingController controller) => controller.text.trim().isNotEmpty);

  String _resolvedReferralCode() {
    if (_hasInviteToken) {
      final String prefilled = _normalizeCode(widget.prefilledReferralCode ?? '');
      if (prefilled.isNotEmpty) {
        return prefilled;
      }
      return BusinessReferralCodeScreen.defaultBusinessReferralCode;
    }

    final String typed = _normalizeCode(_typedCode);
    if (typed.isEmpty) {
      return BusinessReferralCodeScreen.defaultBusinessReferralCode;
    }
    return typed;
  }

  bool _validateCodeEntry() {
    if (_hasInviteToken || _allBoxesEmpty) {
      setState(() => _errorText = null);
      return true;
    }

    if (!_allBoxesFilled || _normalizeCode(_typedCode).length != 8) { // was 6
      setState(() {
        _errorText =
            'Enter the full 8-character referral code or leave all boxes blank.';
      });
      return false;
    }

    setState(() => _errorText = null);
    return true;
  }

  void _handleCodeChanged(int index, String value) {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }

    if (value.isNotEmpty) {
      if (index < _focusNodes.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
  }

  // Backspace pressed while a box is already empty — jump back to the
  // previous box and clear it, so backspace works continuously.
  void _handleBackspaceOnEmpty(int index) {
    if (index <= 0) return;
    _controllers[index - 1].clear();
    _focusNodes[index - 1].requestFocus();
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  Future<void> _goToRegistration(String referralCode) async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            arguments: <String, dynamic>{
              'inviteToken': widget.inviteToken?.trim(),
              'referralCode': referralCode,
              'isInviteFlow': _hasInviteToken,
              'accountType': 'business',
            },
          ),
          builder: (_) => BusinessRegistrationScreen(
            referralCode: referralCode,
            inviteToken: widget.inviteToken?.trim() ?? '',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildCodeBox(int index) {
  return SizedBox(
    width: 40,
    height: 56,
    child: KeyboardListener(
      focusNode: _keyEventFocusNodes[index],
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _controllers[index].text.isEmpty) {
          _handleBackspaceOnEmpty(index);
        }
      },
      child: TextField(
      controller: _controllers[index],
      focusNode: _focusNodes[index],
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.characters,
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
      maxLength: 1,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
        UpperCaseTextFormatter(),
      ],
      decoration: InputDecoration(
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _goOutsBlue, width: 1.4),
        ),
      ),
      onChanged: (String value) => _handleCodeChanged(index, value),
    ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _goOutsBlue,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Referral Code',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 8),
              Center(
                child: Image.asset(
                  'assets/logo/business_code.png',
                  height: 275,
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(height: 20),
              AutoSizeText(
                'Enter Referral Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 10),
              AutoSizeText(
                _hasInviteToken
                    ? 'Your business invite has already been linked.'
                    : 'Enter a referral code if you have one, or continue to use the default business code ${BusinessReferralCodeScreen.defaultBusinessReferralCode}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.black54,
                ),
              ),
              SizedBox(height: 28),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: List<Widget>.generate(
                  8, // was 6
                  (int index) => _buildCodeBox(index),
                ),
              ),
              if (_errorText != null) ...[
                SizedBox(height: 12),
                AutoSizeText(
                  _errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE8EEF3)),
                ),
                child: Text(
                  'Default Business Referral Code: ${BusinessReferralCodeScreen.defaultBusinessReferralCode}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _goOutsBlue,
                  ),
                ),
              ),
              SizedBox(height: 28),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_validateCodeEntry()) {
                            await _goToRegistration(_resolvedReferralCode());
                          }
                        },
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
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// UpperCaseTextFormatter used to be declared here as well as in
// business_registration_screen.dart, which this file imports. Dart lets a
// local declaration shadow an imported one so it compiled, but two public
// classes with one name in a single package is the same shape as the
// GoOutsColors mess still open as issue #127. Removed — the one from
// business_registration_screen.dart is used instead.
