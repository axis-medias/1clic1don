import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:clic_1_don/service/auth_service.dart';

class AppMenu extends StatefulWidget {
  final String currentRoute;

  const AppMenu({super.key, required this.currentRoute});

  @override
  State<AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<AppMenu> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  double _opacity = 0.0; // Pour l'animation globale du menu
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Initialiser l'animation du logo
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    // Déclencher les animations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _opacity = 1.0;
      });
      _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double drawerWidth = MediaQuery.of(context).size.width * 0.75;
    final double logoSize = (drawerWidth * 0.25).clamp(60.0, 100.0); // Responsive logo size
    final double logoPadding = logoSize * 0.2; // Padding proportionnel

    return FutureBuilder<bool>(
      future: _authService.isTokenValid(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Drawer(
            width: drawerWidth,
            child: const Center(child: CircularProgressIndicator(color: Color(0xFFfb8c00))),
          );
        }
        final bool isConnected = snapshot.data ?? false;
        return Drawer(
          width: drawerWidth,
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(milliseconds: 500),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF64b5f6), Color(0xFF1e88e5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16.0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(51),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Semantics(
                            label: 'welcome_logo_label'.tr(),
                            child: Container(
                              padding: EdgeInsets.all(logoPadding),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withAlpha(230),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(26),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: logoSize,
                                height: logoSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                if (isConnected) ...[
                  _buildMenuItem(
                    icon: Icons.home,
                    title: 'home_title'.tr(),
                    route: '/home',
                    isSelected: widget.currentRoute == '/home',
                  ),
                  _buildMenuItem(
                    icon: Icons.list,
                    title: 'cagnotte_list_title'.tr(),
                    route: '/liste-cagnottes',
                    isSelected: widget.currentRoute == '/liste-cagnottes',
                  ),
                  _buildMenuItem(
                    icon: Icons.favorite,
                    title: 'support_association'.tr(),
                    route: '/decouvrir-associations',
                    isSelected: widget.currentRoute == '/decouvrir-associations',
                  ),
                  _buildMenuItem(
                    icon: Icons.monetization_on,
                    title: 'donations_list_title'.tr(),
                    route: '/dons_membre',
                    isSelected: widget.currentRoute == '/dons_membre',
                  ),
                  _buildMenuItem(
                    icon: Icons.person,
                    title: 'profile_title'.tr(),
                    route: '/profile',
                    isSelected: widget.currentRoute == '/profile',
                  ),
                  _buildMenuItem(
                    icon: Icons.settings,
                    title: 'settings_title'.tr(),
                    route: '/settings',
                    isSelected: widget.currentRoute == '/settings',
                  ),
                  _buildMenuItem(
                    icon: Icons.logout,
                    title: 'logout'.tr(),
                    onTap: _logout,
                    isSelected: false,
                  ),
                ] else ...[
                  _buildMenuItem(
                    icon: Icons.home,
                    title: 'home_title'.tr(),
                    route: '/welcome',
                    isSelected: widget.currentRoute == '/welcome',
                  ),
                  _buildMenuItem(
                    icon: Icons.login,
                    title: 'login_title'.tr(),
                    route: '/login',
                    isSelected: widget.currentRoute == '/login',
                  ),
                  _buildMenuItem(
                    icon: Icons.person_add,
                    title: 'register_title'.tr(),
                    route: '/register',
                    isSelected: widget.currentRoute == '/register',
                  ),
                  _buildMenuItem(
                    icon: Icons.list,
                    title: 'cagnotte_list_title'.tr(),
                    route: '/liste-cagnottes',
                    isSelected: widget.currentRoute == '/liste-cagnottes',
                  ),
                  _buildMenuItem(
                    icon: Icons.favorite,
                    title: 'support_association'.tr(),
                    route: '/decouvrir-associations',
                    isSelected: widget.currentRoute == '/decouvrir-associations',
                  ),
                  _buildMenuItem(
                    icon: Icons.settings,
                    title: 'settings_title'.tr(),
                    route: '/settings',
                    isSelected: widget.currentRoute == '/settings',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/splash');
    }
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? route,
    VoidCallback? onTap,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFfb8c00).withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: ListTile(
          leading: Icon(
            icon,
            color: isSelected ? const Color(0xFFfb8c00) : Colors.grey[600],
            size: 28,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isSelected ? const Color(0xFFfb8c00) : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 16,
            ),
          ),
          selected: isSelected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          onTap: () {
            if (onTap != null) {
              onTap();
            } else if (route != null) {
              Navigator.pop(context); // Ferme le Drawer
              Navigator.pushNamed(context, route);
            }
          },
        ),
      ),
    );
  }
}