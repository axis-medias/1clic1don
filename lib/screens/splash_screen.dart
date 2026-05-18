import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
//import 'clic_solidaire.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnimation;
  late Future<bool> _firstVisitFuture;

  int _currentIndex = 0;
  final _authService = AuthService();
  final CarouselSliderController _carouselController = CarouselSliderController();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 1), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
    );

    _buttonController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)..repeat(reverse: true);
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    _controller.forward();
    _firstVisitFuture = _checkLoginAndFirstVisit();
  }

  Future<bool> _checkLoginAndFirstVisit() async {
    try {
      final isValid = await _authService.isTokenValid();
      if (isValid) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
        return false;
      }
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      bool isFirstVisit = prefs.getBool('isFirstVisit') ?? true;
      await Future.delayed(const Duration(seconds: 2));
      return isFirstVisit;
    } catch (e) {
      return true;
    }
  }

  Future<void> _setFirstVisitFalse() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isFirstVisit', false);
  }


  @override
  void dispose() {
    _controller.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double logoSize = isMobile ? 150.0 : 200.0;

    return FutureBuilder<bool>(
      future: _firstVisitFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context, logoSize);
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('error_generic'.tr(args: [snapshot.error.toString()]))),
          );
        }
        return snapshot.data == true
            ? _buildOnboardingScreen(context, logoSize)
            : _buildWelcomeScreen(context, logoSize);
      },
    );
  }

  Widget _buildLoadingScreen(BuildContext context, double logoSize) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
          ),
        ),
        child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding + 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Semantics(
                        label: 'splash_logo_label'.tr(),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xCCFFFFFF), // withAlpha(204) → 0.8 * 255 = 204
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x1A000000), // withAlpha(26) → 26/255 ≈ 0.102
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
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: Color(0xFFfb8c00)),
                ],
              ),
            ),
          ),
      ),
    );
  }

  Widget _buildOnboardingScreen(BuildContext context, double logoSize) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;
    final bool isTablet = screenWidth >= 600 && screenWidth <= 1200;
    final double padding = isMobile ? 16.0 : (isTablet ? 24.0 : 32.0);
    final double titleFontSize = isMobile ? 18.0 : (isTablet ? 22.0 : 26.0);
    final double bodyFontSize = isMobile ? 14.0 : (isTablet ? 16.0 : 18.0);
    final double carouselHeight = MediaQuery.of(context).size.height * 0.4;
    final double buttonWidth = isMobile ? 90.0 : (isTablet ? 100.0 : 130.0);
    final double buttonHeight = isMobile ? 40.0 : (isTablet ? 44.0 : 50.0);
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    final List<Widget> carouselItems = List.generate(4, (index) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xF2FFFFFF), // withAlpha(242) → 242/255 ≈ 0.949
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: _buildCarouselSlide(
            icon: [Icons.volunteer_activism, Icons.play_circle_outline, Icons.favorite, Icons.euro][index],
            title: 'splash_carousel_title_${index + 1}'.tr(),
            description: 'splash_carousel_description_${index + 1}'.tr(),
            color: [const Color(0xFF1e88e5), const Color(0xFF28a745), const Color(0xFFffc107), const Color(0xFF17a2b8)][index],
            isMobile: isMobile,
          ),
        ),
      );
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
          ),
        ),
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              padding,
              padding,
              padding,
              padding + bottomPadding + 40.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 800.0 : double.infinity),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      children: [
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: ScaleTransition(
                            scale: _scaleAnimation,
                            child: Semantics(
                              label: 'splash_logo_label'.tr(),
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: logoSize,
                                height: logoSize,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SlideTransition(
                          position: _slideAnimation,
                          child: Text(
                            'splash_onboarding_title'.tr(),
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1e88e5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'splash_onboarding_subtitle'.tr(),
                          style: TextStyle(fontSize: bodyFontSize, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  CarouselSlider(
                    carouselController: _carouselController,
                    items: carouselItems,
                    options: CarouselOptions(
                      height: carouselHeight,
                      viewportFraction: 0.85,
                      enableInfiniteScroll: false,
                      padEnds: true,
                      enlargeCenterPage: true,
                      initialPage: 0,
                      onPageChanged: (index, reason) => setState(() => _currentIndex = index),
                    ),
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            return Container(
                              width: _currentIndex == index ? 12.0 : 8.0,
                              height: 8.0,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentIndex == index ? const Color(0xFFfb8c00) : Colors.grey.shade300,
                              ),
                            );
                          }),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(padding, 8, padding, 8),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16.0,
                          runSpacing: 12.0,
                          children: [
                            if (_currentIndex > 0)
                              ScaleTransition(
                                scale: _buttonScaleAnimation,
                                child: Semantics(
                                  button: true,
                                  label: 'splash_button_previous'.tr(),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[300],
                                      foregroundColor: Colors.black,
                                      minimumSize: Size(buttonWidth * 0.8, buttonHeight),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 8,
                                      shadowColor: const Color(0x4D808080), // withAlpha(77)
                                    ),
                                    onPressed: () => _carouselController.previousPage(
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    ),
                                    child: Text(
                                      'splash_button_previous'.tr(),
                                      style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ScaleTransition(
                              scale: _buttonScaleAnimation,
                              child: Semantics(
                                button: true,
                                label: _currentIndex < 3 ? 'splash_button_next'.tr() : 'splash_button_finish'.tr(),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1e88e5),
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(buttonWidth * 0.8, buttonHeight),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 8,
                                    shadowColor: const Color(0x4D1E88E5), // withAlpha(77)
                                  ),
                                  onPressed: () {
                                    if (_currentIndex < 3) {
                                      _carouselController.nextPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    } else {
                                      _setFirstVisitFalse();
                                      Navigator.pushNamed(context, '/welcome');
                                    }
                                  },
                                  child: Text(
                                    _currentIndex < 3 ? 'splash_button_next'.tr() : 'splash_button_finish'.tr(),
                                    style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                            ScaleTransition(
                              scale: _buttonScaleAnimation,
                              child: Semantics(
                                button: true,
                                label: 'splash_button_skip'.tr(),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFfb8c00),
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(buttonWidth * 0.8, buttonHeight),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 8,
                                    shadowColor: const Color(0x4DFB8C00), // withAlpha(77)
                                  ),
                                  onPressed: () {
                                    _setFirstVisitFalse();
                                    Navigator.pushNamed(context, '/welcome');
                                  },
                                  child: Text(
                                    'splash_button_skip'.tr(),
                                    style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }

  Widget _buildWelcomeScreen(BuildContext context, double logoSize) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double padding = isMobile ? 16.0 : 24.0;
    final double titleFontSize = isMobile ? 18.0 : 22.0;
    final double buttonWidth = isMobile ? 200.0 : 250.0;
    final double buttonHeight = isMobile ? 40.0 : 48.0;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
          ),
        ),
        child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                padding,
                padding,
                padding + bottomPadding + 40.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Semantics(
                        label: 'splash_logo_label'.tr(),
                        child: Container(
                          padding: EdgeInsets.all(isMobile ? 24.0 : 32.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xCCFFFFFF), // withAlpha(204)
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x1A000000), // withAlpha(26)
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
                  SizedBox(height: isMobile ? 32.0 : 40.0),
                  SlideTransition(
                    position: _slideAnimation,
                    child: Text(
                      'splash_welcome_title'.tr(),
                      style: TextStyle(
                        fontSize: titleFontSize,
                        color: const Color(0xFF1e88e5),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: padding * 2),
                  ScaleTransition(
                    scale: _buttonScaleAnimation,
                    child: Semantics(
                      button: true,
                      label: 'splash_button_login'.tr(),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1e88e5),
                          foregroundColor: Colors.white,
                          minimumSize: Size(buttonWidth, buttonHeight),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: const Color(0x4D1E88E5), // withAlpha(77)
                        ),
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        child: Text(
                          'splash_button_login'.tr(),
                          style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: padding),
                  ScaleTransition(
                    scale: _buttonScaleAnimation,
                    child: Semantics(
                      button: true,
                      label: 'splash_button_signup'.tr(),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFfb8c00),
                          foregroundColor: Colors.white,
                          minimumSize: Size(buttonWidth, buttonHeight),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: const Color(0x4DFB8C00), // withAlpha(77)
                        ),
                        onPressed: () => Navigator.pushNamed(context, '/register'),
                        child: Text(
                          'splash_button_signup'.tr(),
                          style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: padding),
                  // ElevatedButton.icon(
                  //   onPressed: () {
                  //     Navigator.push(
                  //       context,
                  //       MaterialPageRoute(
                  //         builder: (context) => const ClicSolidairePage(
                  //           libelle: 'ASSOCIATION CHEVAL',
                  //           cagnotteId: null,
                  //           associationId: 1,
                  //         ),
                  //       ),
                  //     );
                  //   },
                  //   icon: const Icon(Icons.language, color: Colors.white),
                  //   label: const Text(
                  //     "VISITE SOLIDAIRE (15s)",
                  //     style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  //   ),
                  //   style: ElevatedButton.styleFrom(
                  //     backgroundColor: const Color(0xFF689F38), // Votre vert solidaire
                  //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  //     shape: RoundedRectangleBorder(
                  //       borderRadius: BorderRadius.circular(10),
                  //     ),
                  //   ),
                  // ),
                  Text(
                    'splash_continue_without_signup'.tr(),
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 16,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: padding / 2),
                  ScaleTransition(
                    scale: _buttonScaleAnimation,
                    child: Semantics(
                      button: true,
                      label: 'splash_button_start'.tr(),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          minimumSize: Size(buttonWidth, buttonHeight),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: const Color(0x4D808080), // withAlpha(77)
                        ),
                        onPressed: () {
                          _setFirstVisitFalse();
                          Navigator.pushNamed(context, '/welcome');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_forward, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'splash_button_start'.tr(),
                              style: TextStyle(fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }

  // CORRIGÉ : context supprimé des paramètres
  Widget _buildCarouselSlide({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required bool isMobile,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2), // withAlpha(51) → opacity 0.2
              shape: BoxShape.circle,
            ),
            child: Semantics(
              label: title,
              child: Icon(icon, size: isMobile ? 48 : 64, color: color),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 18 : 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}