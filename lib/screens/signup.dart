import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/scheduler.dart';
import 'login.dart';
import 'app_menu.dart';
import 'package:clic_1_don/service/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pseudoController = TextEditingController();
  final _scrollController = ScrollController();
  final _emailKey = GlobalKey();
  final _pseudoKey = GlobalKey();
  final _passwordKey = GlobalKey();
  final _confirmPasswordKey = GlobalKey();
  final _emailFocusNode = FocusNode();
  final _pseudoFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  final _authService = AuthService();
  bool _newsletter = false;
  String? _errorMessage;
  bool _isLoading = false;
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_scrollToFocusedField);
    _pseudoFocusNode.addListener(_scrollToFocusedField);
    _passwordFocusNode.addListener(_scrollToFocusedField);
    _confirmPasswordFocusNode.addListener(_scrollToFocusedField);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      debugPrint('SignupScreen: Current locale: ${context.locale.languageCode}');
      setState(() {
        _opacity = 1.0;
      });
    });
  }

  void _scrollToFocusedField() {
    if (_emailFocusNode.hasFocus ||
        _pseudoFocusNode.hasFocus ||
        _passwordFocusNode.hasFocus ||
        _confirmPasswordFocusNode.hasFocus) {
      final key = _emailFocusNode.hasFocus
          ? _emailKey
          : _pseudoFocusNode.hasFocus
          ? _pseudoKey
          : _passwordFocusNode.hasFocus
          ? _passwordKey
          : _confirmPasswordKey;
      final context = key.currentContext;
      if (context == null) return;
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final position = renderBox.localToGlobal(Offset.zero);
      final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      final screenHeight = MediaQuery.sizeOf(context).height;
      final offset = position.dy - (screenHeight - keyboardHeight) / 2 + renderBox.size.height / 2;

      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients && mounted) {
          _scrollController.animateTo(
            offset.clamp(0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  bool _validateInputs() {
    if (_emailController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'signup_error_email_required'.tr());
      return false;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text)) {
      setState(() => _errorMessage = 'signup_error_email_invalid'.tr());
      return false;
    }
    if (_pseudoController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'signup_error_pseudo_required'.tr());
      return false;
    }
    if (_pseudoController.text.length < 3 || _pseudoController.text.length > 20) {
      setState(() => _errorMessage = 'signup_error_pseudo_length'.tr());
      return false;
    }
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(_pseudoController.text)) {
      setState(() => _errorMessage = 'signup_error_pseudo_chars'.tr());
      return false;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'signup_error_password_required'.tr());
      return false;
    }
    if (_passwordController.text.length < 8) {
      setState(() => _errorMessage = 'signup_error_password_length'.tr());
      return false;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'profile_error_password_mismatch'.tr());
      return false;
    }
    return true;
  }

  Future<void> _signup() async {
    if (!_validateInputs()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final String lang = context.locale.languageCode;
      debugPrint('SignupScreen: Sending signup request with lang=$lang');
      final url = Uri.parse('https://www.1clic1don.fr/app/signup.php?lang=$lang');
      final body = json.encode({
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'newsletter': _newsletter,
        'pseudo': _pseudoController.text.trim(),
      });
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      debugPrint('SignupScreen: Response from signup.php: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('signup_success'.tr())),
            );
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          }
        } else {
          setState(() {
            final messages = (data['message'] as String).split(' ');
            _errorMessage = messages.map((msg) => msg.tr()).join(' ');
            if (_errorMessage!.isEmpty) {
              _errorMessage = 'signup_error_default'.tr();
            }
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'signup_error_default'.tr(args: [response.statusCode.toString()]);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'signup_error_network'.tr();
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePop() async {
    final isValid = await _authService.isTokenValid();
    if (!mounted) return;
    if (!isValid) {
      Navigator.of(context).pushReplacementNamed('/splash');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pseudoController.dispose();
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _pseudoFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double padding = isMobile ? 16.0 : 24.0;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'register_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          backgroundColor: const Color(0xFF1e88e5),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: false,
          leading: Builder(
            builder: (context) {
              return IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
                tooltip: 'welcome_menu_tooltip'.tr(),
              );
            },
          ),
        ),
        drawer: const AppMenu(currentRoute: '/register'),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF0F4FE), Color(0xFFF8F9FA)],
            ),
          ),
          child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(
                padding,
                padding,
                padding,
                padding + bottomPadding + keyboardHeight + 40.0,
              ),
              child: Center(
                child: AnimatedOpacity(
                  opacity: _opacity,
                  duration: const Duration(milliseconds: 500),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.0),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.102), // Remplacement de withAlpha(26)
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'signup_welcome'.tr(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1e88e5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          key: _emailKey,
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          decoration: InputDecoration(
                            labelText: 'login_email_label'.tr(),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                            prefixIcon: const Icon(Icons.email, color: Color(0xFF1e88e5)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: _pseudoKey,
                          controller: _pseudoController,
                          focusNode: _pseudoFocusNode,
                          decoration: InputDecoration(
                            labelText: 'profile_pseudo_label'.tr(),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                            prefixIcon: const Icon(Icons.person, color: Color(0xFF1e88e5)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: _passwordKey,
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          decoration: InputDecoration(
                            labelText: 'profile_new_password_label'.tr(),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFF1e88e5)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: _confirmPasswordKey,
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          decoration: InputDecoration(
                            labelText: 'profile_confirm_password_label'.tr(),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFF1e88e5)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          title: Text(
                            'profile_newsletter_label'.tr(),
                            style: const TextStyle(fontSize: 14),
                          ),
                          value: _newsletter,
                          onChanged: (value) => setState(() => _newsletter = value ?? false),
                          activeColor: const Color(0xFF1e88e5),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _isLoading
                            ? const CircularProgressIndicator(color: Color(0xFF1e88e5))
                            : ElevatedButton(
                          onPressed: _signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1e88e5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                            minimumSize: const Size(double.infinity, 48),
                            elevation: 2,
                          ),
                          child: Text(
                            'splash_button_signup'.tr(),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/login'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'signup_login_prompt'.tr(),
                              style: const TextStyle(
                                color: Color(0xFF1e88e5),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ),
      ),
    );
  }
}