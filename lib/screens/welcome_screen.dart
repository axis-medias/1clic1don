import 'package:flutter/material.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:clic_1_don/screens/app_menu.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:clic_1_don/screens/cagnotte.dart';
import 'package:clic_1_don/models/association.dart';
import 'package:clic_1_don/models/donation_args.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mes_favoris_associations_screen.dart';
import 'mes_favoris_cagnottes_screen.dart';

// Catégories communes
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

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _buttonController;
  late Animation<double> _buttonScaleAnimation;
  final _authService = AuthService();

  // Compteurs de favoris
  int _favoritesAssociationsCount = 0;
  int _favoritesCagnottesCount = 0;

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
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
    );
    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );
    _controller.forward();
    _loadFavoritesCount();
  }

  Future<void> _loadFavoritesCount() async {
    final prefs = await SharedPreferences.getInstance();
    final associations = prefs.getStringList('favorites_associations') ?? [];
    final cagnottes = prefs.getStringList('favorites_cagnottes') ?? [];
    if (mounted) {
      setState(() {
        _favoritesAssociationsCount = associations.length;
        _favoritesCagnottesCount = cagnottes.length;
      });
    }
  }

  Future<void> _handlePop() async {
    final isValid = await _authService.isTokenValid();
    if (!mounted) return;
    if (!isValid) {
      debugPrint('WelcomeScreen: Token invalid, redirecting to /splash');
      Navigator.of(context).pushReplacementNamed('/splash');
    }
  }

  Future<Map<String, dynamic>> _fetchFeaturedCagnotte() async {
    try {
      final String languageCode = context.locale.languageCode;
      debugPrint('WelcomeScreen: Fetching featured cagnotte with lang=$languageCode');
      final Uri uri = Uri.parse('https://www.1clic1don.fr/app/cagnotte-top.php').replace(
        queryParameters: {'lang': languageCode},
      );
      final response = await http.get(uri);
      debugPrint('WelcomeScreen: Response from cagnotte-top.php: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final result = data['data'] as Map<String, dynamic>;
          final titre = result['titre'];
          final descriptionCourte = result['descriptionCourte'];
          debugPrint('WelcomeScreen: titre = "$titre", descriptionCourte = "$descriptionCourte"');
          return {
            'id': result['id'] ?? 1,
            'titre': (titre != null && titre.toString().trim().isNotEmpty) ? titre.toString().trim() : 'cagnotte_default_name'.tr(),
            'descriptionCourte': (descriptionCourte != null && descriptionCourte.toString().trim().isNotEmpty)
                ? descriptionCourte.toString().trim()
                : 'cagnotte_no_description'.tr(),
            'imageUrl': result['imageUrl'] ?? '',
            'idCategorie': result['id_categorie'] ?? 1,
            'mode': result['mode'] ?? 'PONCTUELLE',
            'objectif_monetaire': result['objectif_monetaire'] ?? 0,
            'solde_Current': result['solde_current'] ?? 0,
          };
        } else {
          throw Exception(data['message']?.toString().tr() ?? 'cagnotte_no_active_found'.tr());
        }
      } else {
        throw Exception('error_server'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('WelcomeScreen: Error fetching featured cagnotte: $e');
      return {
        'id': 1,
        'titre': 'cagnotte_default_name'.tr(),
        'descriptionCourte': 'cagnotte_no_description'.tr(),
        'imageUrl': '',
        'idCategorie': 1,
        'mode': 'PONCTUELLE',
        'objectif_monetaire': 100000,
        'solde_Current': 0,
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
      debugPrint('WelcomeScreen: Response from association_top.php: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final result = data['data'] as Map<String, dynamic>;
          final titre = result['titre'];
          final descriptionCourte = result['descriptionCourte'];
          debugPrint('WelcomeScreen: titre = "$titre", descriptionCourte = "$descriptionCourte"');
          return {
            'id': result['id'],
            'titre': result['titre']?.isNotEmpty == true ? result['titre'] : 'association_default_name'.tr(),
            'descriptionCourte': result['descriptionCourte']?.isNotEmpty == true ? result['descriptionCourte'] : 'association_no_description'.tr(),
            'imageUrl': result['imageUrl'] ?? '',
            'idCategorie': result['id_categorie'] ?? 1,
          };
        } else {
          throw Exception(data['message'].tr());
        }
      } else {
        throw Exception('error_server'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('WelcomeScreen: Error fetching featured association: $e');
      return {
        'id': 1,
        'titre': 'association_default_name'.tr(),
        'descriptionCourte': 'association_no_description'.tr(),
        'imageUrl': '',
        'idCategorie': 1,
      };
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
    final double titleFontSize = isMobile ? 18.0 : (isTablet ? 22.0 : 26.0);
    final double bodyFontSize = isMobile ? 14.0 : (isTablet ? 16.0 : 18.0);
    final double logoSize = isMobile ? 150.0 : 200.0;
    final double buttonWidth = isMobile ? MediaQuery.of(context).size.width * 0.7 : (isTablet ? 280.0 : 320.0);
    final double buttonHeight = isMobile ? 56.0 : (isTablet ? 64.0 : 72.0);
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        debugPrint('WelcomeScreen: Back button pressed');
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'app_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          backgroundColor: const Color(0xFF1e88e5),
          centerTitle: true,
          elevation: 4,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: false,
          leading: Builder(
            builder: (context) {
              debugPrint('WelcomeScreen: Leading hamburger button rendered');
              return IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  debugPrint('WelcomeScreen: Hamburger button pressed');
                  Scaffold.of(context).openDrawer();
                },
                tooltip: 'welcome_menu_tooltip'.tr(),
              );
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () async {
                await SharePlus.instance.share(ShareParams(text:'welcome_share_text'.tr()));
              },
            ),
          ],
        ),
        drawer: const AppMenu(currentRoute: '/welcome'),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
            ),
          ),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isTablet ? 800.0 : 1200.0),
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + bottomPadding + 40),
                child: Column(
                  children: [
                    // En-tête
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
                        const SizedBox(height: 16),
                        SlideTransition(
                          position: _slideAnimation,
                          child: Text(
                            'welcome_header_title'.tr(),
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1e88e5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'welcome_header_subtitle'.tr(),
                          style: TextStyle(
                            fontSize: bodyFontSize,
                            color: Colors.grey[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    // Boutons principaux
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16.0,
                        runSpacing: 16.0,
                        children: [
                          SizedBox(
                            width: buttonWidth,
                            child: ScaleTransition(
                              scale: _buttonScaleAnimation,
                              child: Semantics(
                                button: true,
                                label: 'welcome_button_cagnottes'.tr(),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1e88e5),
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(buttonWidth, buttonHeight),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 8,
                                    shadowColor: const Color(0xFF1e88e5).withAlpha(77),
                                  ),
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/liste-cagnottes');
                                  },
                                  child: Text(
                                    'welcome_button_cagnottes'.tr(),
                                    style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: ScaleTransition(
                              scale: _buttonScaleAnimation,
                              child: Semantics(
                                button: true,
                                label: 'support_association'.tr(),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFfb8c00),
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(buttonWidth, buttonHeight),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    elevation: 8,
                                    shadowColor: const Color(0xFFfb8c00).withAlpha(77),
                                  ),
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/decouvrir-associations');
                                  },
                                  child: Text(
                                    'support_association'.tr(),
                                    style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Hub des favoris (uniquement si au moins un favori)
                    // Section Favoris - toujours visible (deux blocs indépendants)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
                      child: Column(
                        children: [
                          // Titre principal de la section
                          Text(
                            'welcome_favorites_hub_title'.tr(),
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1e88e5),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Bloc Associations favorites
                          _buildFavoriFullBlock(
                            icon: Icons.business,
                            title: 'associations_favorites'.tr(),
                            count: _favoritesAssociationsCount,
                            colorStart: const Color(0xFF1e88e5),
                            colorEnd: const Color(0xFF1565c0),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const MesFavorisAssociationsScreen()),
                              ).then((_) => _loadFavoritesCount()); // ← ajout du then
                            },
                          ),
                          const SizedBox(height: 16),

                          // Bloc Cagnottes favorites
                          _buildFavoriFullBlock(
                            icon: Icons.savings,
                            title: 'cagnottes_favorites'.tr(),
                            count: _favoritesCagnottesCount,
                            colorStart: const Color(0xFFfb8c00),
                            colorEnd: const Color(0xFFe65100),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const MesFavorisCagnottesScreen()),
                              ).then((_) => _loadFavoritesCount()); // ← ajout du then
                            },
                          ),
                        ],
                      ),
                    ),
                    // Section "Cagnotte à la une"
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
                      child: Column(
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
                                titre: data['titre'] ?? 'welcome_cagnotte_default_title'.tr(),
                                descriptionCourte: data['descriptionCourte'] ?? 'welcome_cagnotte_default_description'.tr(),
                                descriptionLongue: data['descriptionLongue'] ?? 'cagnotte_description_long'.tr(),
                                imageUrl: data['imageUrl'] ?? '',
                                idCategorie: data['idCategorie'] ?? 1,
                                soldeCurrent: (data['solde_Current'] as num?)?.toDouble() ?? 0.0,
                                objectifMonetaire: (data['objectif_monetaire'] as num?)?.toDouble() ?? 100000,
                                mode: data['mode'] ?? 'PONCTUELLE',
                                association: data['association'] != null ? Association.fromJson(data['association']) : null,
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
                    ),
                    // Section "Association à la une"
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
                      child: Column(
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
                                nom: data['titre'] ?? 'welcome_association_default_title'.tr(),
                                description: data['descriptionCourte'] ?? 'welcome_association_default_description'.tr(),
                                logoUrl: data['imageUrl'] ?? '',
                                idcategorie: data['idCategorie'] ?? 1,
                              );
                              return _buildFeaturedCard(
                                cagnotte: null,
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
                    ),
                    // Statistiques
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Column(
                            children: [
                              Text(
                                '+10 000',
                                style: TextStyle(
                                  fontSize: bodyFontSize + 2,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFfb8c00),
                                ),
                              ),
                              Text(
                                'welcome_stats_donors'.tr(),
                                style: TextStyle(fontSize: bodyFontSize, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                '+300',
                                style: TextStyle(
                                  fontSize: bodyFontSize + 2,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFfb8c00),
                                ),
                              ),
                              Text(
                                'welcome_stats_associations'.tr(),
                                style: TextStyle(fontSize: bodyFontSize, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Connexion/Inscription
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: padding),
                      child: Column(
                        children: [
                          Text(
                            'welcome_join_community'.tr(),
                            style: TextStyle(
                              fontSize: bodyFontSize,
                              color: Colors.grey[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16.0,
                            runSpacing: 16.0,
                            children: [
                              SizedBox(
                                width: buttonWidth,
                                child: ScaleTransition(
                                  scale: _buttonScaleAnimation,
                                  child: Semantics(
                                    button: true,
                                    label: 'splash_button_login'.tr(),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1e88e5),
                                        foregroundColor: Colors.white,
                                        minimumSize: Size(buttonWidth, buttonHeight),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 4,
                                      ),
                                      onPressed: () {
                                        Navigator.pushNamed(context, '/login');
                                      },
                                      child: Text(
                                        'splash_button_login'.tr(),
                                        style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: buttonWidth,
                                child: ScaleTransition(
                                  scale: _buttonScaleAnimation,
                                  child: Semantics(
                                    button: true,
                                    label: 'splash_button_signup'.tr(),
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFfb8c00),
                                        foregroundColor: Colors.white,
                                        minimumSize: Size(buttonWidth, buttonHeight),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 4,
                                      ),
                                      onPressed: () {
                                        Navigator.pushNamed(context, '/register');
                                      },
                                      child: Text(
                                        'splash_button_signup'.tr(),
                                        style: TextStyle(fontSize: bodyFontSize, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildFavoriFullBlock({
    required IconData icon,
    required String title,
    required int count,
    required Color colorStart,
    required Color colorEnd,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorStart, colorEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colorStart.withAlpha(51),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icône
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 16),
            // Texte et compteur
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${'welcome_favorites_count'.tr()} : $count',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            // Flèche
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
          ],
        ),
      ),
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
    final title = cagnotte?.titre ?? association?.nom ?? 'welcome_cagnotte_default_title'.tr();
    final description = cagnotte?.descriptionCourte ?? association?.description ?? 'welcome_cagnotte_default_description'.tr();
    final imageUrl = cagnotte?.imageUrl ?? association?.logoUrl ?? '';

    int categoryId = 1;
    if (cagnotte != null) {
      categoryId = cagnotte.idCategorie;
    } else if (association != null) {
      categoryId = association.idcategorie;
    }
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
      } else {
        return Icon(
          categoryInfo.icon,
          size: 60,
          color: categoryInfo.color,
        );
      }
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
                    SizedBox(
                      width: buttonWidth,
                      child: ScaleTransition(
                        scale: _buttonScaleAnimation,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1e88e5),
                            foregroundColor: Colors.white,
                            minimumSize: Size(buttonWidth, buttonHeight),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                          onPressed: () async {
                            if (cagnotte != null) {
                              await Navigator.pushNamed(context, detailRoute, arguments: cagnotte);
                            } else if (association != null) {
                              await Navigator.pushNamed(context, detailRoute, arguments: association);
                            }
                            _loadFavoritesCount(); // ← Rafraîchit les compteurs
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: buttonWidth,
                      child: ScaleTransition(
                        scale: _buttonScaleAnimation,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5733),
                            foregroundColor: Colors.white,
                            minimumSize: Size(buttonWidth, buttonHeight),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                          ),
                          onPressed: () async {
                            if (cagnotte != null) {
                              await Navigator.pushNamed(
                                context,
                                donationRoute,
                                arguments: DonationArgs(type: 'cagnotte', id: cagnotte.id, libelle: cagnotte.titre),
                              );
                            } else if (association != null) {
                              await Navigator.pushNamed(
                                context,
                                donationRoute,
                                arguments: DonationArgs(type: 'association', id: association.id, libelle: association.nom),
                              );
                            }
                            _loadFavoritesCount(); // ← Rafraîchit les compteurs
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