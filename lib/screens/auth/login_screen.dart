import 'package:flutter/material.dart';
import 'package:emergencies_disability_assistance_app/models/caregiver_model.dart';
import 'package:emergencies_disability_assistance_app/screens/caregiver/caregiver_root_screen.dart';
import 'package:emergencies_disability_assistance_app/screens/user/user_root_screen.dart';
import 'package:emergencies_disability_assistance_app/services/auth_service.dart';

import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.prefilledEmail});

  factory LoginScreen.prefilled(String email, {Key? key}) {
    return LoginScreen(key: key, prefilledEmail: email);
  }

  final String? prefilledEmail;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailErrorText;
  String? _passwordErrorText;

  static final _emailRegex = RegExp(r'^[\w\.-]+@[\w\.-]+\.[a-zA-Z]{2,}$');

  bool get _isFormFilled =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.prefilledEmail ?? '';
    _emailController.addListener(_handleFieldChange);
    _passwordController.addListener(_handleFieldChange);
  }

  @override
  void dispose() {
    _emailController
      ..removeListener(_handleFieldChange)
      ..dispose();
    _passwordController
      ..removeListener(_handleFieldChange)
      ..dispose();
    super.dispose();
  }

  void _handleFieldChange() {
    setState(() {
      _emailErrorText = null;
      _passwordErrorText = null;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final result = await _authService.loginUser(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!result.signedIn) {
      final code = result.errorCode ?? 'unknown';
      final message = switch (code) {
        'network-request-failed' =>
          'No internet/DNS. Please turn on Wi‑Fi/mobile data and try again.',
        'invalid-credential' =>
          'Invalid credentials. Please check your email and password.',
        'user-not-found' =>
          'Account not found. Please check your email or register.',
        'wrong-password' => 'Incorrect password. Please try again.',
        'too-many-requests' =>
          'Too many attempts. Please wait and try again later.',
        _ =>
          'Login failed. Please double-check your email and password, then try again.',
      };
      _showErrorDialog(title: 'Login failed', message: message);
      return;
    }

    if (!result.hasProfile) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _showSnack(
        'Signed in, but failed to load your profile. Check internet/App Check then try again.',
      );
      return;
    }

    final profile = result.profile;
    final Widget destination = profile is CaregiverModel
        ? const CaregiverRootScreen()
        : const UserRootScreen();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.black87),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4B63D),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color accentYellow = Color(0xFFF4B63D);
    const Color disabledGrey = Color(0xFFE5E5E5);
    const Color signUpColor = Color(0xFF00A8A7);
    final textTheme = Theme.of(context).textTheme;
    final bool canSubmit = _isFormFilled && !_isLoading;
    final Color buttonColor = canSubmit ? accentYellow : disabledGrey;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Transform.translate(
                          offset: const Offset(-8, 0),
                          child: IconButton(
                            style: IconButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(36, 36),
                              shape: const CircleBorder(),
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Log in to your ElderAssist account',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildInputField(
                              label: 'Your email',
                              hintText: 'name@example.com',
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              icon: Icons.mail_outline_rounded,
                              errorText: _emailErrorText,
                            ),
                            const SizedBox(height: 16),
                            _buildInputField(
                              label: 'Password',
                              hintText: 'Password',
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              icon: Icons.lock_outline_rounded,
                              errorText: _passwordErrorText,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.grey[600],
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canSubmit ? _loginUser : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            foregroundColor: canSubmit
                                ? Colors.black
                                : Colors.white70,
                            elevation: canSubmit ? 2 : 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text('Continue'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'New to ElderAssist?',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: signUpColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            child: const Text('Sign up'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required String hintText,
    required TextEditingController controller,
    required IconData icon,
    bool obscureText = false,
    String? errorText,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    final Color errorColor = Colors.red.shade400;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (value) {
            if (errorText != null) return errorText;
            if (value == null || value.trim().isEmpty) {
              return 'This field is required.';
            }
            if (keyboardType == TextInputType.emailAddress &&
                !_emailRegex.hasMatch(value.trim())) {
              return 'Invalid email.';
            }
            return null;
          },
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.white,
            prefixIcon: Icon(icon, color: Colors.grey[600]),
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.black87, width: 1.2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: errorColor, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: errorColor, width: 1.3),
            ),
            errorStyle: TextStyle(color: errorColor, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
