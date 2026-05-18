import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/scheduler.dart';
import 'app_menu.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _scrollController = ScrollController();
  final _emailKey = GlobalKey();
  final _passwordKey = GlobalKey();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  String? _errorMessage;
  bool _isLoading = false;
  double _opacity = 0.0;
  bool _obscurePassword = true; // ← AJOUTÉ : État pour masquer/afficher le mot de passe

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_scrollToFocusedField);
    _passwordFocusNode.addListener(_scrollToFocusedField);
    _emailController.addListener(_updateButtonState);
    _passwordController.addListener(_updateButtonState);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      debugPrint('LoginScreen: Current locale: ${context.locale.languageCode}');
      setState(() {
        _opacity = 1.0;
      });
    });
  }

  void _updateButtonState() {
    setState(() {});
  }

  void _scrollToFocusedField() {
    if (_emailFocusNode.hasFocus || _passwordFocusNode.hasFocus) {
      final key = _emailFocusNode.hasFocus ? _emailKey : _passwordKey;
      final context = key.currentContext;
      if (context == null) return;
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final position = renderBox.localToGlobal(Offset.zero);
      final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      final screenHeight = MediaQuery.sizeOf(context).height;
      final offset = position.dy - (screenHeight - keyboardHeight) / 3 + renderBox.size.height / 2;
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
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'login_error_invalid_credentials'.tr();
      });
      return false;
    }
    return true;
  }

  Future<void> _login() async {
    if (!_validateInputs()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final String lang = context.locale.languageCode;
      final token = await FirebaseMessaging.instance.getToken();
      final url = Uri.parse('https://www.1clic1don.fr/app/login.php?lang=$lang');
      final body = json.encode({
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'device_token': token,
      });
      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      )
          .timeout(const Duration(seconds: 5));
      debugPrint('LoginScreen: Response from login.php: ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          if (data['jwt'] == null || data['refresh_token'] == null || data['member_id'] == null || data['pseudo'] == null) {
            setState(() {
              _errorMessage = 'login_error_incomplete_response'.tr();
              _isLoading = false;
            });
            return;
          }
          await _authService.saveAuthData(
            jwt: data['jwt'],
            refreshToken: data['refresh_token'],
            memberId: data['member_id'].toString(),
            pseudo: data['pseudo'],
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('login_success'.tr())),
            );
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          }
        } else {
          setState(() {
            _errorMessage = data['message'].tr();
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'login_error_default'.tr(args: [response.statusCode.toString()]);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'login_error_network'.tr();
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
    _emailController.removeListener(_updateButtonState);
    _passwordController.removeListener(_updateButtonState);
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
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
            'login_title'.tr(),
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
        drawer: const AppMenu(currentRoute: '/login'),
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
                          color: Color.fromRGBO(0, 0, 0, 0.102),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'login_welcome'.tr(),
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            prefixIcon: const Icon(Icons.email, color: Color(0xFF1e88e5)),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        // ← MODIFIÉ : Champ mot de passe avec toggle
                        TextField(
                          key: _passwordKey,
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          decoration: InputDecoration(
                            labelText: 'login_password_label'.tr(),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFF1e88e5)),
                            // ← AJOUTÉ : Icône suffixIcon pour toggle
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                color: Color(0xFF1e88e5),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              tooltip: _obscurePassword
                                  ? 'login_show_password'.tr()
                                  : 'login_hide_password'.tr(),
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          obscureText: _obscurePassword, // ← MODIFIÉ : Variable dynamique
                        ),
                        const SizedBox(height: 16),
                        if (_errorMessage != null)
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
                        const SizedBox(height: 16),
                        _isLoading
                            ? const CircularProgressIndicator(color: Color(0xFF1e88e5))
                            : ElevatedButton(
                          onPressed: _emailController.text.trim().isEmpty || _passwordController.text.isEmpty
                              ? null
                              : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1e88e5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            minimumSize: const Size(double.infinity, 48),
                            elevation: 2,
                          ),
                          child: Text(
                            'splash_button_login'.tr(),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/register');
                          },
                          child: Text(
                            'login_signup_prompt'.tr(),
                            style: const TextStyle(
                              color: Color(0xFF1e88e5),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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