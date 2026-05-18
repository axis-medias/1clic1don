import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:clic_1_don/screens/app_menu.dart';
import 'package:clic_1_don/screens/cagnotte.dart';
import 'package:clic_1_don/models/association.dart';
import 'package:clic_1_don/models/donation_args.dart';
import 'package:cached_network_image/cached_network_image.dart';

const Map<int, CategoryInfo> categoriesInfo = {
  1: CategoryInfo('category_animals', Color(0xFF1e88e5), Icons.pets),
  2: CategoryInfo('category_environment', Color(0xFF689f38), Icons.eco),
  3: CategoryInfo('category_humanitarian', Color(0xFFfb8c00), Icons.volunteer_activism),
  4: CategoryInfo('category_media_culture', Color(0xFF9c27b0), Icons.movie),
};

class CategoryInfo {
  final String nameKey;
  final Color color;
  final IconData icon;
  const CategoryInfo(this.nameKey, this.color, this.icon);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _authService = AuthService();

  String? _pseudo;
  bool _isLoading = true;
  bool _didInitDependencies = false;

  Map<String, dynamic>? _badgeData;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_didInitDependencies) {
      _didInitDependencies = true;
      final languageCode = context.locale.languageCode;
      _initialize(languageCode);
    }
  }

  Future<void> _initialize(String languageCode) async {
    try {
      final isValid = await _authService.isTokenValid();

      if (!isValid) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/splash');
        }
        return;
      }

      final pseudo = await _authService.getPseudo();

      Map<String, dynamic>? badge;
      try {
        badge = await _fetchBadge(languageCode);
      } catch (e) {
        debugPrint('Erreur chargement badge ignorée: $e');
        badge = null;
      }

      if (!mounted) return;

      setState(() {
        _pseudo = pseudo;
        _badgeData = badge;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.pushReplacementNamed(context, '/splash');
    }
  }

  Future<Map<String, dynamic>?> _fetchBadge(String languageCode) async {
    try {
      final token = await _authService.getJwt();

      if (token == null || token.isEmpty) {
        return null;
      }

      final Uri uri = Uri.parse('https://www.1clic1don.fr/app/get_badge.php').replace(
        queryParameters: {
          'lang': languageCode,
        },
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('BADGE status: ${response.statusCode}');
      debugPrint('BADGE body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true && data['data'] != null) {
          return data['data'] as Map<String, dynamic>;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Erreur badge: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _fetchFeaturedCagnotte() async {
    try {
      final String languageCode = context.locale.languageCode;

      final Uri uri = Uri.parse('https://www.1clic1don.fr/app/cagnotte-top.php').replace(
        queryParameters: {'lang': languageCode},
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final result = data['data'] as Map<String, dynamic>;
          final titre = result['titre'];
          final descriptionCourte = result['descriptionCourte'];

          return {
            'id': result['id'] ?? 1,
            'titre': (titre != null && titre.toString().trim().isNotEmpty)
                ? titre.toString().trim()
                : 'cagnotte_default_name'.tr(),
            'descriptionCourte': (descriptionCourte != null && descriptionCourte.toString().trim().isNotEmpty)
                ? descriptionCourte.toString().trim()
                : 'cagnotte_no_description'.tr(),
            'imageUrl': result['imageUrl'] ?? '',
            'idCategorie': result['id_categorie'] ?? 1,
            'mode': result['mode'] ?? 'PONCTUELLE',
            'objectif_monetaire': result['objectif_monetaire'] ?? 0,
            'solde_current': result['solde_current'] ?? 0,
          };
        } else {
          throw Exception(data['message']?.toString().tr() ?? 'cagnotte_no_active_found'.tr());
        }
      } else {
        throw Exception('error_server'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      return {
        'id': 1,
        'titre': 'cagnotte_default_name'.tr(),
        'descriptionCourte': 'cagnotte_no_description'.tr(),
        'imageUrl': '',
        'idCategorie': 1,
        'mode': 'PONCTUELLE',
        'objectif_monetaire': 100000,
        'solde_current': 0,
      };
    }
  }

  Future<Map<String, dynamic>> _fetchFeaturedAssociation() async {
    try {
      final String languageCode = context.locale.languageCode;

      final Uri uri = Uri.parse('https://www.1clic1don.fr/app/association-top.php').replace(
        queryParameters: {'lang': languageCode},
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final result = data['data'] as Map<String, dynamic>;
          final titre = result['titre'];
          final descriptionCourte = result['descriptionCourte'];

          return {
            'id': result['id'] ?? 1,
            'titre': (titre != null && titre.toString().trim().isNotEmpty)
                ? titre.toString().trim()
                : 'association_default_name'.tr(),
            'descriptionCourte': (descriptionCourte != null && descriptionCourte.toString().trim().isNotEmpty)
                ? descriptionCourte.toString().trim()
                : 'association_no_description'.tr(),
            'imageUrl': result['imageUrl'] ?? '',
            'idCategorie': result['id_categorie'] ?? 1,
          };
        } else {
          throw Exception(data['message']?.toString().tr() ?? 'association_no_active_found'.tr());
        }
      } else {
        throw Exception('error_server'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      return {
        'id': 1,
        'titre': 'association_default_name'.tr(),
        'descriptionCourte': 'association_no_description'.tr(),
        'imageUrl': '',
        'idCategorie': 1,
      };
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
    _controller.dispose();
    _buttonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final bool isTablet = MediaQuery.of(context).size.width >= 600 && MediaQuery.of(context).size.width <= 1200;

    final double padding = isMobile ? 16.0 : (isTablet ? 24.0 : 32.0);
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double titleFontSize = isMobile ? 18.0 : (isTablet ? 22.0 : 26.0);
    final double bodyFontSize = isMobile ? 14.0 : (isTablet ? 16.0 : 18.0);
    final double logoSize = isMobile ? 120.0 : 150.0;
    final double buttonWidth = isMobile ? MediaQuery.of(context).size.width * 0.7 : (isTablet ? 250.0 : 300.0);
    final double buttonHeight = isMobile ? 48.0 : (isTablet ? 56.0 : 64.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'home_welcome_title'.tr(),
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
        drawer: const AppMenu(currentRoute: '/home'),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFfb8c00)))
              : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              padding,
              padding,
              padding,
              padding + bottomPadding + 40.0,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 800.0 : 1200.0),
              child: Column(
                children: [
                  Column(
                    children: [
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Semantics(
                            label: 'welcome_logo_label'.tr(),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color.fromRGBO(255, 255, 255, 0.902),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, 0.102),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
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
                      const SizedBox(height: 16),
                      SlideTransition(
                        position: _slideAnimation,
                        child: Text(
                          _pseudo != null ? 'welcome_user'.tr(args: [_pseudo!]) : 'home_welcome_no_user'.tr(),
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1e88e5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),

                  if (_badgeData != null) ...[
                    _buildBadgeCard(
                      isMobile: isMobile,
                      bodyFontSize: bodyFontSize,
                    ),
                    const SizedBox(height: 20),
                  ],

                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16.0,
                    runSpacing: 16.0,
                    children: [
                      ScaleTransition(
                        scale: _buttonScaleAnimation,
                        child: Semantics(
                          button: true,
                          label: 'welcome_button_cagnottes'.tr(),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1e88e5),
                              foregroundColor: Colors.white,
                              minimumSize: Size(buttonWidth, buttonHeight),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 8,
                              shadowColor: const Color.fromRGBO(30, 136, 229, 0.302),
                            ),
                            onPressed: () {
                              Navigator.pushNamed(context, '/liste-cagnottes');
                            },
                            child: Text(
                              'welcome_button_cagnottes'.tr(),
                              style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      ScaleTransition(
                        scale: _buttonScaleAnimation,
                        child: Semantics(
                          button: true,
                          label: 'support_association'.tr(),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFfb8c00),
                              foregroundColor: Colors.white,
                              minimumSize: Size(buttonWidth, buttonHeight),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 8,
                              shadowColor: const Color.fromRGBO(251, 140, 0, 0.302),
                            ),
                            onPressed: () {
                              Navigator.pushNamed(context, '/decouvrir-associations');
                            },
                            child: Text(
                              'support_association'.tr(),
                              style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: Text(
                          'welcome_featured_cagnotte_title'.tr(),
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1e88e5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _fetchFeaturedCagnotte(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFFfb8c00)));
                          }

                          if (snapshot.hasError || !snapshot.hasData) {
                            return _buildErrorCard('welcome_cagnotte_error'.tr(), isMobile, bodyFontSize);
                          }

                          final data = snapshot.data!;

                          final cagnotte = Cagnotte(
                            id: data['id'] ?? 1,
                            titre: data['titre'] ?? 'cagnotte_default_name'.tr(),
                            descriptionCourte: data['descriptionCourte'] ?? 'cagnotte_no_description'.tr(),
                            descriptionLongue: 'cagnotte_description_long'.tr(),
                            imageUrl: data['imageUrl'] ?? '',
                            idCategorie: data['idCategorie'] ?? 1,
                            soldeCurrent: (data['solde_current'] as num?)?.toDouble() ?? 0.0,
                            objectifMonetaire: (data['objectif_monetaire'] as num?)?.toDouble() ?? 100000,
                            mode: data['mode'] ?? 'PONCTUELLE',
                            association: null,
                          );

                          return _buildFeaturedCard(
                            cagnotte: cagnotte,
                            isMobile: isMobile,
                            bodyFontSize: bodyFontSize,
                            detailRoute: '/cagnotte',
                            donationRoute: '/donate',
                            buttonWidth: buttonWidth,
                            buttonHeight: buttonHeight,
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: Text(
                          'welcome_featured_association_title'.tr(),
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1e88e5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _fetchFeaturedAssociation(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Color(0xFFfb8c00)));
                          }

                          if (snapshot.hasError || !snapshot.hasData) {
                            return _buildErrorCard('welcome_association_error'.tr(), isMobile, bodyFontSize);
                          }

                          final data = snapshot.data!;

                          final association = Association(
                            id: data['id'] ?? 1,
                            nom: data['titre'] ?? 'association_default_name'.tr(),
                            description: data['descriptionCourte'] ?? 'association_no_description'.tr(),
                            logoUrl: data['imageUrl'] ?? '',
                            idcategorie: data['idCategorie'] ?? 1,
                          );

                          return _buildFeaturedCard(
                            association: association,
                            isMobile: isMobile,
                            bodyFontSize: bodyFontSize,
                            detailRoute: '/association',
                            donationRoute: '/donate',
                            buttonWidth: buttonWidth,
                            buttonHeight: buttonHeight,
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeCard({
    required bool isMobile,
    required double bodyFontSize,
  }) {
    final badge = _badgeData?['badge'] as Map<String, dynamic>?;
    final streak = _badgeData?['streak'] as Map<String, dynamic>?;
    final nextBadge = _badgeData?['next_badge'] as Map<String, dynamic>?;

    if (badge == null) {
      return const SizedBox.shrink();
    }

    final String badgeName = badge['name']?.toString() ?? '';
    final String badgeDescription = badge['description']?.toString() ?? '';
    final String badgeIcon = badge['icon_url']?.toString() ?? '';

    final int streakDays = int.tryParse((streak?['days'] ?? 0).toString()) ?? 0;

    final String? nextBadgeName = nextBadge?['name']?.toString();
    final int remainingDays = int.tryParse((nextBadge?['remaining_days'] ?? 0).toString()) ?? 0;

    return Card(
      elevation: 7,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFFF8E8),
            ],
          ),
          border: Border.all(
            color: Color.fromRGBO(251, 140, 0, 0.25),
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Text(
              'current_badge'.tr(),
              style: TextStyle(
                fontSize: bodyFontSize + 5,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFfb8c00),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            GestureDetector(
              onTap: badgeIcon.isEmpty
                  ? null
                  : () {
                _showBadgeDialog(
                  badgeName: badgeName,
                  badgeDescription: badgeDescription,
                  badgeIcon: badgeIcon,
                  streakDays: streakDays,
                  bodyFontSize: bodyFontSize,
                );
              },
              child: Hero(
                tag: 'current_badge',
                child: CachedNetworkImage(
                  imageUrl: badgeIcon,
                  width: isMobile ? 115 : 145,
                  height: isMobile ? 115 : 145,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const SizedBox(
                    width: 90,
                    height: 90,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFfb8c00),
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.emoji_events,
                    size: 90,
                    color: Color(0xFFfb8c00),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Text(
              badgeName,
              style: TextStyle(
                fontSize: bodyFontSize + 3,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1e88e5),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 6),

            Text(
              badgeDescription,
              style: TextStyle(
                fontSize: bodyFontSize,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(251, 140, 0, 0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                '${'current_streak'.tr()} : $streakDays',
                style: TextStyle(
                  fontSize: bodyFontSize,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFfb8c00),
                ),
              ),
            ),

            if (nextBadgeName != null && nextBadgeName.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                remainingDays > 0
                    ? '${'next_badge_progress'.tr()} : $nextBadgeName — ${'remaining_days'.tr(args: [remainingDays.toString()])}'
                    : '${'next_badge_progress'.tr()} : $nextBadgeName',
                style: TextStyle(
                  fontSize: bodyFontSize - 1,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 8),

            Text(
              'tap_badge_to_enlarge'.tr(),
              style: TextStyle(
                fontSize: bodyFontSize - 2,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showBadgeDialog({
    required String badgeName,
    required String badgeDescription,
    required String badgeIcon,
    required int streakDays,
    required double bodyFontSize,
  }) {
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: 'current_badge',
                  child: CachedNetworkImage(
                    imageUrl: badgeIcon,
                    width: 260,
                    height: 260,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const SizedBox(
                      width: 120,
                      height: 120,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFfb8c00),
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.emoji_events,
                      size: 120,
                      color: Color(0xFFfb8c00),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  badgeName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: bodyFontSize + 8,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1e88e5),
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  badgeDescription,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    color: Colors.grey[700],
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  '${'current_streak'.tr()} : $streakDays',
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFfb8c00),
                  ),
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1e88e5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('close'.tr()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturedCard({
    Cagnotte? cagnotte,
    Association? association,
    required bool isMobile,
    required double bodyFontSize,
    required String detailRoute,
    required String donationRoute,
    required double buttonWidth,
    required double buttonHeight,
  }) {
    final title = cagnotte?.titre ?? association?.nom ?? 'cagnotte_default_name'.tr();
    final description = cagnotte?.descriptionCourte ?? association?.description ?? 'cagnotte_no_description'.tr();
    final imageUrl = cagnotte?.imageUrl ?? association?.logoUrl ?? '';
    final int categoryId = cagnotte?.idCategorie ?? association?.idcategorie ?? 1;
    final categoryInfo = categoriesInfo[categoryId] ?? categoriesInfo[1]!;

    Widget buildImage() {
      if (imageUrl.isNotEmpty && (imageUrl.startsWith('http') || imageUrl.startsWith('https'))) {
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(color: Colors.grey[200]),
          errorWidget: (_, _, _) => Icon(
            categoryInfo.icon,
            size: 60,
            color: categoryInfo.color,
          ),
        );
      }

      return Icon(
        categoryInfo.icon,
        size: 60,
        color: categoryInfo.color,
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              height: isMobile ? 150 : 200,
              width: double.infinity,
              color: Colors.grey[200],
              child: Center(child: buildImage()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: bodyFontSize + 2,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1e88e5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    color: Colors.grey[700],
                  ),
                  maxLines: isMobile ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: _buttonScaleAnimation,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1e88e5),
                          foregroundColor: Colors.white,
                          minimumSize: Size(double.infinity, buttonHeight),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                        ),
                        icon: const Icon(Icons.visibility, size: 20),
                        label: Text(
                          'welcome_button_details'.tr(),
                          style: TextStyle(
                            fontSize: bodyFontSize + 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          if (cagnotte != null) {
                            Navigator.pushNamed(context, detailRoute, arguments: cagnotte);
                          } else if (association != null) {
                            Navigator.pushNamed(context, detailRoute, arguments: association);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    ScaleTransition(
                      scale: _buttonScaleAnimation,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5733),
                          foregroundColor: Colors.white,
                          minimumSize: Size(double.infinity, buttonHeight),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                        ),
                        onPressed: () {
                          if (cagnotte != null) {
                            Navigator.pushNamed(
                              context,
                              donationRoute,
                              arguments: DonationArgs(
                                type: 'cagnotte',
                                id: cagnotte.id,
                                libelle: cagnotte.titre,
                              ),
                            );
                          } else if (association != null) {
                            Navigator.pushNamed(
                              context,
                              donationRoute,
                              arguments: DonationArgs(
                                type: 'association',
                                id: association.id,
                                libelle: association.nom,
                              ),
                            );
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.card_giftcard, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'welcome_button_donate'.tr(),
                              style: TextStyle(
                                fontSize: bodyFontSize + 2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message, bool isMobile, double bodyFontSize) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(fontSize: bodyFontSize, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}