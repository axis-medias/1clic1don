import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'app_menu.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _pseudoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _newsletter = false;
  bool _rappelDon = false;
  bool _isLoading = true;
  String? _errorMessage;
  String? _successMessage;
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    _loadProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _opacity = 1.0);
    });
  }

  Future<void> _loadProfile() async {
    try {
      final isValid = await _authService.isTokenValid();
      if (!isValid) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('profile_session_expired'.tr())),
          );
        }
        return;
      }

      final jwt = await _authService.getJwt();
      if (jwt == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'profile_error_auth'.tr();
        });
        return;
      }

      final url = Uri.parse('https://www.1clic1don.fr/app/get_profile.php');
      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $jwt'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _pseudoController.text = data['pseudo'] ?? '';
            _emailController.text = data['email'] ?? '';
            _newsletter = data['newsletter'] ?? false;
            _rappelDon = data['rappel_don'] ?? false;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = data['message'].tr();
          });
        }
      } else {
        final error = jsonDecode(response.body)['message'] ?? 'error_unknown_api'.tr();
        setState(() {
          _isLoading = false;
          _errorMessage = 'profile_error_loading'.tr(args: [error]);
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'profile_error_loading'.tr(args: [e.toString()]);
      });
    }
  }

  Future<void> _updateProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final pseudo = _pseudoController.text.trim();
    if (pseudo.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'profile_error_pseudo_required'.tr();
      });
      return;
    }

    if (_passwordController.text.isNotEmpty &&
        _passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'profile_error_password_mismatch'.tr();
      });
      return;
    }

    if (_emailController.text.isNotEmpty &&
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(_emailController.text)) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'profile_error_invalid_email'.tr();
      });
      return;
    }

    final result = await _authService.updateProfile(
      pseudo: _pseudoController.text.isNotEmpty ? _pseudoController.text : null,
      email: _emailController.text.isNotEmpty ? _emailController.text : null,
      password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      newsletter: _newsletter,
      rappelDon: _rappelDon,
    );

    setState(() {
      _isLoading = false;
      if (result['success']) {
        _successMessage = (result['message'] as String).tr();
        _passwordController.clear();
        _confirmPasswordController.clear();
      } else {
        _errorMessage = (result['message'] as String).tr();
      }
    });
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
    _pseudoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double formWidth = MediaQuery.of(context).size.width < 600
        ? MediaQuery.of(context).size.width * 0.9
        : 400.0;

    final bottomPadding = MediaQuery.of(context).padding.bottom + 40; // +40px pour sécurité

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'profile_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          backgroundColor: const Color(0xFF1e88e5),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: false,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'welcome_menu_tooltip'.tr(),
            ),
          ),
        ),
        drawer: const AppMenu(currentRoute: '/profile'),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
            ),
          ),
            child: _isLoading
                ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFfb8c00)),
            )
                : AnimatedOpacity(
              opacity: _opacity,
              duration: const Duration(milliseconds: 500),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: constraints.maxWidth < 600 ? 16.0 : 24.0,
                      right: constraints.maxWidth < 600 ? 16.0 : 24.0,
                      top: 24.0,
                      bottom: bottomPadding,
                    ),
                    child: Column(
                      children: [
                        // Formulaire centré horizontalement
                        Center(
                          child: Container(
                            width: formWidth,
                            padding: const EdgeInsets.all(24.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16.0),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'profile_edit_info'.tr(),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1e88e5),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                _buildTextField(
                                  controller: _pseudoController,
                                  label: 'profile_pseudo_label'.tr(),
                                  icon: Icons.person,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _emailController,
                                  label: 'login_email_label'.tr(),
                                  icon: Icons.email,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _passwordController,
                                  label: 'profile_new_password_label'.tr(),
                                  icon: Icons.lock,
                                  obscureText: true,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _confirmPasswordController,
                                  label: 'profile_confirm_password_label'.tr(),
                                  icon: Icons.lock,
                                  obscureText: true,
                                ),
                                const SizedBox(height: 16),
                                _buildCheckbox(
                                  title: 'profile_newsletter_label'.tr(),
                                  value: _newsletter,
                                  onChanged: (v) => setState(() => _newsletter = v ?? false),
                                ),
                                const SizedBox(height: 12),
                                _buildCheckbox(
                                  title: 'profile_donation_reminder_label'.tr(),
                                  value: _rappelDon,
                                  onChanged: (v) => setState(() => _rappelDon = v ?? false),
                                ),
                                const SizedBox(height: 16),
                                if (_errorMessage != null) _buildMessage(_errorMessage!, Colors.red),
                                if (_successMessage != null) _buildMessage(_successMessage!, Colors.green),
                                if (_errorMessage != null || _successMessage != null)
                                  const SizedBox(height: 16),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _updateProfile,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFfb8c00),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12.0),
                                      ),
                                      elevation: 4,
                                      shadowColor: const Color(0x33000000),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                        : Text(
                                      'profile_update_button'.tr(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20), // Espace final
                      ],
                    ),
                  );
                },
              ),
            ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF1e88e5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(color: Color(0xFF1e88e5), width: 2),
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF1e88e5)),
        filled: true,
        fillColor: Colors.grey[100],
      ),
    );
  }

  Widget _buildCheckbox({
    required String title,
    required bool value,
    required void Function(bool?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000), // Remplacé withAlpha(13)
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: CheckboxListTile(
        title: Text(title),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF1e88e5),
        checkColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    );
  }

  Widget _buildMessage(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: color.withAlpha(26), // Remplacé withAlpha(26)
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }
}