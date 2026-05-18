import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:clic_1_don/models/association.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/scheduler.dart';
import 'app_menu.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:clic_1_don/models/donation_args.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clic_1_don/screens/association_paiements_screen.dart';

// Catégories communes (identique au site web)
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

class AssociationDetailScreen extends StatefulWidget {
  final Association association;
  final int? idCagnotte;

  const AssociationDetailScreen({
    super.key,
    required this.association,
    this.idCagnotte,
  });

  @override
  State<AssociationDetailScreen> createState() => _AssociationDetailScreenState();
}

class _AssociationDetailScreenState extends State<AssociationDetailScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  bool isLoading = true;
  String? errorMessage;
  late Association detailedAssociation;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Map<String, dynamic>? _shareData;

  // Favoris
  bool _isFavorite = false;
  bool _isFavoriteLoading = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    detailedAssociation = widget.association;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadAssociationDetails();
      _loadFavoriteState();
    });
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAssociationDetails() async {
    try {
      final String lang = context.locale.languageCode;
      final response = await http.get(
        Uri.parse('https://www.1clic1don.fr/app/association.php?id=${widget.association.id}&lang=$lang'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            detailedAssociation = Association.fromJson(data['association']);
            _shareData = data['share'];
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = context.tr(data['message']);
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'error_server'.tr(args: [response.statusCode.toString()]);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'association_error_network'.tr();
        isLoading = false;
      });
    }
  }

  Future<void> _loadFavoriteState() async {
    final isLoggedIn = await _authService.isTokenValid();
    final associationId = detailedAssociation.id;

    if (isLoggedIn) {
      final memberId = await _authService.getMemberId();
      if (memberId != null) {
        try {
          final response = await http.get(
            Uri.parse('https://www.1clic1don.fr/app/check_favorite.php?type=association&id=$associationId&member_id=$memberId'),
          );
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            setState(() {
              _isFavorite = data['is_favorite'] ?? false;
            });
          } else {
            setState(() => _isFavorite = false);
          }
        } catch (e) {
          debugPrint('Erreur chargement favori: $e');
          setState(() => _isFavorite = false);
        }
      } else {
        setState(() => _isFavorite = false);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites_associations') ?? [];
      setState(() {
        _isFavorite = favorites.contains(associationId.toString());
      });
    }
  }

  Future<void> _saveFavoriteLocally(bool isFavorite) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites_associations') ?? [];
    if (isFavorite) {
      if (!favorites.contains(detailedAssociation.id.toString())) {
        favorites.add(detailedAssociation.id.toString());
      }
    } else {
      favorites.remove(detailedAssociation.id.toString());
    }
    await prefs.setStringList('favorites_associations', favorites);
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading) return;
    setState(() => _isFavoriteLoading = true);

    final isLoggedIn = await _authService.isTokenValid();
    final associationId = detailedAssociation.id;
    final wasFavorite = _isFavorite;

    try {
      if (isLoggedIn) {
        final memberId = await _authService.getMemberId();
        if (memberId == null) throw Exception('Utilisateur non identifié');
        final action = wasFavorite ? 'remove' : 'add';
        final response = await http.post(
          Uri.parse('https://www.1clic1don.fr/app/ajax-favori.php'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'type': 'association',
            'id': associationId,
            'action': action,
            'member_id': memberId,
          }),
        );
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            setState(() {
              _isFavorite = !wasFavorite;
            });
          }
          await _saveFavoriteLocally(!wasFavorite);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_isFavorite ? 'association_added_favorite'.tr() : 'association_removed_favorite'.tr())),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Erreur');
        }
      } else {
        await _saveFavoriteLocally(!wasFavorite);
        if (mounted) {
          setState(() {
            _isFavorite = !wasFavorite;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isFavorite ? 'association_added_favorite'.tr() : 'association_removed_favorite'.tr())),
          );
        }
      }
    } catch (e) {
      debugPrint('Erreur toggle favorite: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_favorite_action'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isFavoriteLoading = false);
    }
  }

  Future<void> _launchUrl(String? url) async {
    if (url != null) {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_unable_open_link'.tr())),
        );
      }
    }
  }

  Future<void> _handlePop() async {
    final isValid = await _authService.isTokenValid();
    if (!mounted) return;
    if (!isValid) {
      Navigator.pushReplacementNamed(context, '/splash');
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = isLoading
        ? (widget.association.nom == 'Association inconnue' ? 'association_default_name'.tr() : widget.association.nom)
        : (detailedAssociation.nom == 'Association inconnue' ? 'association_default_name'.tr() : detailedAssociation.nom);
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            displayName.toUpperCase(),
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
              return IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
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
                if (_shareData != null && _shareData!['text'] != null && _shareData!['url'] != null) {
                  final shareText = _shareData!['text'].toString().tr(args: [displayName, _shareData!['url']]);
                  await SharePlus.instance.share(ShareParams(text: shareText));
                } else {
                  final url = 'https://www.1clic1don.fr/association.php?id=${widget.association.id}';
                  final shareText = 'association_share_text_2'.tr(args: [displayName, url]);
                  await SharePlus.instance.share(ShareParams(text: shareText));
                }
              },
            ),
          ],
        ),
        drawer: const AppMenu(currentRoute: '/association'),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
            ),
          ),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : errorMessage != null
              ? _buildErrorWidget()
              : FadeTransition(
            opacity: _fadeAnimation,
            child: _buildContent(bottomPadding),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 50, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            errorMessage ?? 'association_not_found'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              setState(() {
                isLoading = true;
                errorMessage = null;
              });
              SchedulerBinding.instance.addPostFrameCallback((_) {
                _loadAssociationDetails();
              });
            },
            child: Text('error_retry_button'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(double bottomPadding) {
    final displayName = detailedAssociation.nom == 'Association inconnue' ? 'association_default_name'.tr() : detailedAssociation.nom;
    final category = categoriesInfo[detailedAssociation.idcategorie] ?? categoriesInfo[1]!;
    final bool isMobile = MediaQuery.of(context).size.width < 600;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0 + bottomPadding + 40),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(180),
                          const SizedBox(height: 8),
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.launch, size: 20, color: Colors.white),
                            label: Text(
                              'association_visit_website'.tr(),
                              style: const TextStyle(fontSize: 16),
                            ),
                            onPressed: () => _launchUrl(detailedAssociation.siteUrl),
                          ),
                          if (widget.idCagnotte == null) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF5733),
                                foregroundColor: Colors.white,
                                minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                elevation: 2,
                                shadowColor: Color.fromRGBO(0, 0, 0, 0.2),
                              ),
                              icon: const Icon(Icons.card_giftcard, size: 20, color: Colors.white),
                              label: Text(
                                'association_donate_button'.tr(),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                if (mounted) {
                                  Navigator.pushNamed(
                                    context,
                                    '/donate',
                                    arguments: DonationArgs(
                                      type: 'association',
                                      id: detailedAssociation.id,
                                      libelle: displayName,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFavorite ? Colors.red : Colors.grey,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                            ),
                            icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, size: 20),
                            label: Text(_isFavorite ? 'association_remove_favorite_tooltip'.tr() : 'association_add_favorite_tooltip'.tr()),
                            onPressed: _isFavoriteLoading ? null : _toggleFavorite,
                          ),
                          const SizedBox(height: 20),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                            ),
                            icon: const Icon(Icons.history, size: 20),
                            label: Text('Historique des paiements'.tr()),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AssociationPaiementsScreen(associationId: detailedAssociation.id),
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          Text(
                            'association_share_title'.tr(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.share, size: 24),
                            label: Text(
                              'association_share_button'.tr(),
                              style: const TextStyle(fontSize: 16),
                            ),
                            onPressed: () async {
                              if (_shareData != null && _shareData!['text'] != null && _shareData!['url'] != null) {
                                final shareText = _shareData!['text'].toString().tr(
                                  args: [displayName, _shareData!['url']],
                                );
                                await SharePlus.instance.share(ShareParams(text: shareText));
                              } else {
                                final url = 'https://www.1clic1don.fr/association.php?id=${widget.association.id}';
                                final shareText = 'association_share_text_2'.tr(args: [displayName, url]);
                                await SharePlus.instance.share(ShareParams(text: shareText));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsCard(category, isMobile),
                  if (detailedAssociation.imageUrl != null)
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final double imageWidth = constraints.maxWidth;
                            const aspectRatio = 4 / 3;
                            final double imageHeight = imageWidth / aspectRatio;
                            return SizedBox(
                              width: imageWidth,
                              height: imageHeight,
                              child: CachedNetworkImage(
                                imageUrl: detailedAssociation.imageUrl!,
                                fit: BoxFit.contain,
                                placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                                errorWidget: (_, _, _) => Icon(
                                  category.icon,
                                  size: 50,
                                  color: category.color,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'association_about_title'.tr(),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
                          ),
                          const SizedBox(height: 12),
                          Html(
                            data: detailedAssociation.description ?? 'association_no_description'.tr(),
                            style: {
                              'body': Style(
                                fontSize: FontSize(18),
                                lineHeight: const LineHeight(1.8),
                                margin: Margins.zero,
                              ),
                              'p': Style(
                                margin: Margins.only(bottom: 8.0),
                              ),
                              'a': Style(
                                color: Colors.blue,
                                textDecoration: TextDecoration.underline,
                              ),
                            },
                            onLinkTap: (url, attributes, element) => _launchUrl(url),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            } else {
              // Version desktop (tablette/PC)
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatsCard(category, isMobile),
                        if (detailedAssociation.imageUrl != null)
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final double imageWidth = constraints.maxWidth;
                                  const aspectRatio = 4 / 3;
                                  final double imageHeight = imageWidth / aspectRatio;
                                  return SizedBox(
                                    width: imageWidth,
                                    height: imageHeight,
                                    child: CachedNetworkImage(
                                      imageUrl: detailedAssociation.imageUrl!,
                                      fit: BoxFit.contain,
                                      placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                                      errorWidget: (_, _, _) => Icon(
                                        category.icon,
                                        size: 50,
                                        color: category.color,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'association_about_title'.tr(),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                Html(
                                  data: detailedAssociation.description ?? 'association_no_description'.tr(),
                                  style: {
                                    'body': Style(
                                      fontSize: FontSize(16),
                                      lineHeight: const LineHeight(1.8),
                                      margin: Margins.zero,
                                    ),
                                    'p': Style(
                                      margin: Margins.only(bottom: 8.0),
                                    ),
                                    'a': Style(
                                      color: Colors.blue,
                                      textDecoration: TextDecoration.underline,
                                    ),
                                  },
                                  onLinkTap: (url, attributes, element) => _launchUrl(url),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(180),
                            const SizedBox(height: 8),
                            Text(
                              displayName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _launchUrl(detailedAssociation.siteUrl),
                              child: Text(
                                'association_visit_website'.tr(),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            if (widget.idCagnotte == null) ...[
                              const SizedBox(height: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFfb8c00),
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(double.infinity, isMobile ? 40 : 36),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                                ),
                                onPressed: () {
                                  if (mounted) {
                                    Navigator.pushNamed(
                                      context,
                                      '/donate',
                                      arguments: DonationArgs(
                                        type: 'association',
                                        id: detailedAssociation.id,
                                        libelle: displayName,
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  'association_donate_button'.tr(),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFavorite ? Colors.red : Colors.grey,
                                foregroundColor: Colors.white,
                                minimumSize: Size(double.infinity, isMobile ? 40 : 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                              ),
                              icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, size: 20),
                              label: Text(_isFavorite ? 'association_remove_favorite_tooltip'.tr() : 'association_add_favorite_tooltip'.tr()),
                              onPressed: _isFavoriteLoading ? null : _toggleFavorite,
                            ),
                            const SizedBox(height: 20),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                              ),
                              icon: const Icon(Icons.history, size: 20),
                              label: Text('Historique des paiements'.tr()),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AssociationPaiementsScreen(associationId: detailedAssociation.id),
                                  ),
                                );
                              },
                            ),
                            const Divider(),
                            Text(
                              'association_share_title'.tr(),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.share, size: 24),
                              label: Text(
                                'association_share_button'.tr(),
                                style: const TextStyle(fontSize: 16),
                              ),
                              onPressed: () async {
                                if (_shareData != null && _shareData!['text'] != null && _shareData!['url'] != null) {
                                  final shareText = _shareData!['text'].toString().tr(
                                    args: [displayName, _shareData!['url']],
                                  );
                                  await SharePlus.instance.share(ShareParams(text: shareText));
                                } else {
                                  final url = 'https://www.1clic1don.fr/association.php?id=${widget.association.id}';
                                  final shareText = 'association_share_text_2'.tr(args: [displayName, url]);
                                  await SharePlus.instance.share(ShareParams(text: shareText));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildHeader(double height) {
    final category = categoriesInfo[detailedAssociation.idcategorie] ?? categoriesInfo[1]!;
    final hasLogo = detailedAssociation.logoUrl != null && detailedAssociation.logoUrl!.isNotEmpty;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12.0)),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              category.color.withAlpha(51),
              category.color.withAlpha(26),
            ],
          ),
        ),
        child: hasLogo
            ? CachedNetworkImage(
          imageUrl: detailedAssociation.logoUrl!,
          fit: BoxFit.contain,
          placeholder: (_, _) => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          errorWidget: (_, _, _) => Icon(
            category.icon,
            size: height * 0.35,
            color: category.color,
          ),
        )
            : Icon(
          category.icon,
          size: height * 0.35,
          color: category.color,
        ),
      ),
    );
  }

  Widget _buildStatsCard(CategoryInfo category, bool isMobile) {
    final double balance = detailedAssociation.balance ?? 0.0;
    final double totalPaid = detailedAssociation.totalPaid ?? 0.0;

    String formatMoney(double amount) {
      final locale = context.locale.languageCode == 'fr' ? 'fr_FR' : 'en_US';
      return NumberFormat('#,##0.00', locale).format(amount);
    }

    String formatMoneyGoal(double amount) {
      final locale = context.locale.languageCode == 'fr' ? 'fr_FR' : 'en_US';
      return NumberFormat('#,##0.000', locale).format(amount);
    }

    String? badgeText;
    Color badgeBgColor = Colors.grey.shade600;
    Color badgeTextColor = Colors.white;
    final double seuilVirement = detailedAssociation.minSoldePourVirement ?? 15.0;

    if (balance >= seuilVirement) {
      badgeText = "virement_imminent".tr();
      badgeBgColor = Colors.white;
      badgeTextColor = Colors.black87;
    } else if (balance > 0) {
      badgeText = "encore_x_euro".tr(args: [formatMoneyGoal(seuilVirement - balance)]);
      badgeBgColor = Colors.amber.shade700;
      badgeTextColor = Colors.white;
    } else {
      badgeText = "en_attente_vues".tr();
    }

    Widget buildStat({
      required IconData icon,
      required String value,
      required String label,
      String? badge,
    }) => Column(
      children: [
        Icon(icon, size: 48, color: Colors.white.withAlpha(242)),
        const SizedBox(height: 16),
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 14)).tr(),
        if (badge != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: badgeBgColor,
              borderRadius: BorderRadius.circular(30),
              border: badgeBgColor == category.color.withAlpha(229)
                  ? Border.all(color: Colors.white.withAlpha(76), width: 1.5)
                  : null,
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 6, offset: const Offset(0, 3)),
              ],
            ),
            child: Text(
              badge,
              style: TextStyle(color: badgeTextColor, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
            ),
          ),
        ],
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 24, bottom: 32),
      child: Material(
        elevation: 18,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [category.color, category.color.withAlpha(224)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -70,
                right: -70,
                child: Opacity(
                  opacity: 0.14,
                  child: Transform.rotate(
                    angle: 0.25,
                    child: const Icon(Icons.favorite, size: 220, color: Colors.white),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text(
                      "impact_global".tr(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 12, color: Colors.black26, offset: Offset(0, 4)),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isSmall = constraints.maxWidth < 420;
                      if (isSmall) {
                        return Column(
                          children: [
                            Center(
                              child: buildStat(
                                icon: Icons.account_balance_wallet,
                                value: "${formatMoneyGoal(balance)} €",
                                label: "solde_actuel",
                                badge: badgeText,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Center(
                              child: buildStat(
                                icon: Icons.volunteer_activism,
                                value: "${formatMoney(totalPaid)} €",
                                label: "deja_verse",
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            buildStat(
                              icon: Icons.account_balance_wallet,
                              value: "${formatMoneyGoal(balance)} €",
                              label: "solde_actuel",
                              badge: badgeText,
                            ),
                            buildStat(
                              icon: Icons.volunteer_activism,
                              value: "${formatMoney(totalPaid)} €",
                              label: "deja_verse",
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}