import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:confetti/confetti.dart';
import 'package:clic_1_don/models/association.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_menu.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:clic_1_don/models/donation_args.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clic_1_don/screens/cagnotte_paiements_screen.dart';

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

class Cagnotte {
  final int id;
  final String titre;
  final String descriptionCourte;
  final String descriptionLongue;
  final String imageUrl;
  final int idCategorie;
  final double soldeCurrent;
  final double objectifMonetaire;
  final String mode;  // "PONCTUELLE" ou "PERMANENTE"
  final Association? association;

  Cagnotte({
    required this.id,
    required this.titre,
    required this.descriptionCourte,
    required this.descriptionLongue,
    required this.imageUrl,
    required this.idCategorie,
    required this.soldeCurrent,
    required this.objectifMonetaire,
    required this.mode,
    this.association,
  });

  factory Cagnotte.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return Cagnotte(
      id: json['id'] as int? ?? 0,
      titre: json['libelle'] as String? ?? 'cagnotte_default_title'.tr(),
      descriptionCourte: json['description_courte'] as String? ?? 'cagnotte_default_description_short'.tr(),
      descriptionLongue: json['description_longue'] as String? ?? 'cagnotte_default_description_long'.tr(),
      imageUrl: (json['img_projet_min'] as String?) ?? (json['img_projet'] as String?) ?? '',
      idCategorie: json['id_categorie'] as int? ?? 0,
      soldeCurrent: parseDouble(json['solde_current']),
      objectifMonetaire: parseDouble(json['objectif_monetaire']),
      mode: (json['mode'] as String?) ?? 'PONCTUELLE',
      association: json['association'] != null ? Association.fromJson(json['association']) : null,
    );
  }

  bool get isPermanente => mode == 'PERMANENTE';
}

class CagnotteDetailScreen extends StatefulWidget {
  final Cagnotte cagnotte;
  const CagnotteDetailScreen({super.key, required this.cagnotte});

  @override
  State<CagnotteDetailScreen> createState() => _CagnotteDetailScreenState();
}

class _CagnotteDetailScreenState extends State<CagnotteDetailScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  bool isLoading = true;
  String? errorMessage;
  late Cagnotte detailedCagnotte;
  String? shareText;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late ConfettiController _confettiController;
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
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    detailedCagnotte = widget.cagnotte;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadCagnotteDetails();
      _loadFavoriteState();
    });
    _animationController.forward();
  }

  Future<void> _loadCagnotteDetails() async {
    try {
      final String lang = context.locale.languageCode;
      final response = await http.get(
        Uri.parse('https://www.1clic1don.fr/app/cagnotte.php?id=${widget.cagnotte.id}&lang=$lang'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            detailedCagnotte = Cagnotte.fromJson({
              ...data['projet'],
              'association': data['association'],
            });
            _shareData = data['share'];
            isLoading = false;
          });
          if (mounted &&
              !detailedCagnotte.isPermanente &&
              detailedCagnotte.soldeCurrent >= detailedCagnotte.objectifMonetaire) {
            _confettiController.play();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('cagnotte_goal_reached_snackbar'.tr()),
                backgroundColor: const Color(0xFF1e88e5),
              ),
            );
          }
        } else {
          setState(() {
            errorMessage = context.tr(data['message']);
            isLoading = false;
          });
        }
      } else {
        errorMessage = 'error_server'.tr(args: [response.statusCode.toString()]);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'association_error_network'.tr();
          isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteState() async {
    final isLoggedIn = await _authService.isTokenValid();
    final cagnotteId = detailedCagnotte.id;

    if (isLoggedIn) {
      final memberId = await _authService.getMemberId();
      if (memberId != null) {
        try {
          final response = await http.get(
            Uri.parse('https://www.1clic1don.fr/app/check_favorite.php?type=cagnotte&id=$cagnotteId&member_id=$memberId'),
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
          debugPrint('Erreur chargement favori cagnotte: $e');
          setState(() => _isFavorite = false);
        }
      } else {
        setState(() => _isFavorite = false);
      }
    } else {
      // Non connecté : lecture SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites_cagnottes') ?? [];
      setState(() {
        _isFavorite = favorites.contains(cagnotteId.toString());
      });
    }
  }

  Future<void> _saveFavoriteLocally(bool isFavorite) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites_cagnottes') ?? [];
    if (isFavorite) {
      if (!favorites.contains(detailedCagnotte.id.toString())) {
        favorites.add(detailedCagnotte.id.toString());
      }
    } else {
      favorites.remove(detailedCagnotte.id.toString());
    }
    await prefs.setStringList('favorites_cagnottes', favorites);
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading) return;
    setState(() => _isFavoriteLoading = true);

    final isLoggedIn = await _authService.isTokenValid();
    final cagnotteId = detailedCagnotte.id;
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
            'type': 'cagnotte',
            'id': cagnotteId,
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
              SnackBar(content: Text(_isFavorite ? 'cagnotte_added_favorite'.tr() : 'cagnotte_removed_favorite'.tr())),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Erreur');
        }
      } else {
        // Non connecté : stockage local uniquement
        await _saveFavoriteLocally(!wasFavorite);
        if (mounted) {
          setState(() {
            _isFavorite = !wasFavorite;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isFavorite ? 'cagnotte_added_favorite'.tr() : 'cagnotte_removed_favorite'.tr())),
          );
        }
      }
    } catch (e) {
      debugPrint('Erreur toggle favorite cagnotte: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_favorite_action'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isFavoriteLoading = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  String getProgressLabel(double solde) {
    if (solde >= detailedCagnotte.objectifMonetaire) return 'cagnotte_progress_goal_reached'.tr();
    if (solde >= detailedCagnotte.objectifMonetaire * 0.75) return 'cagnotte_progress_almost_reached'.tr();
    if (solde >= detailedCagnotte.objectifMonetaire * 0.5) return 'cagnotte_progress_halfway'.tr();
    if (solde >= detailedCagnotte.objectifMonetaire * 0.25) return 'cagnotte_progress_on_track'.tr();
    return 'cagnotte_progress_starting'.tr();
  }

  double getProgress(double solde) {
    return (solde / detailedCagnotte.objectifMonetaire).clamp(0.0, 1.0);
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
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double padding = isMobile ? 8.0 : 12.0;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: Text(
                detailedCagnotte.titre,
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
                    debugPrint('CagnotteDetailScreen: AppBar share - _shareData = $_shareData');
                    if (_shareData != null && _shareData!['text'] != null && _shareData!['url'] != null) {
                      final shareText = _shareData!['text'].toString().tr(args: [detailedCagnotte.titre, _shareData!['url']]);
                      debugPrint('CagnotteDetailScreen: AppBar share - shareText = $shareText');
                      await SharePlus.instance.share(ShareParams(text:shareText));
                    } else {
                      final url = 'https://www.1clic1don.fr/cagnotte.php?id=${detailedCagnotte.id}';
                      final shareText = 'cagnotte_share_text_2'.tr(args: [detailedCagnotte.titre, url]);
                      debugPrint('CagnotteDetailScreen: AppBar share - shareText (fallback) = $shareText');
                      await SharePlus.instance.share(ShareParams(text:shareText));
                    }
                  },
                ),
              ],
            ),
            drawer: const AppMenu(currentRoute: '/cagnotte'),
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
                ),
              ),
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFfb8c00)))
                  : errorMessage != null
                  ? _buildErrorWidget()
                  : FadeTransition(
                opacity: _fadeAnimation,
                child: _buildContent(padding, isMobile, bottomPadding),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Color(0xFFfb8c00), Color(0xFF1e88e5)],
              numberOfParticles: 50,
              maxBlastForce: 100,
              minBlastForce: 50,
            ),
          ),
        ],
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
            errorMessage ?? 'cagnotte_not_found'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFfb8c00),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text('cagnotte_back_to_list'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(double padding, bool isMobile, double bottomPadding) {
    String formatMoney(double amount) {
      final locale = context.locale.languageCode == 'fr' ? 'fr_FR' : 'en_US';
      return NumberFormat('#,##0.00', locale).format(amount);
    }
    String formatMoneyGoal(double amount) {
      final locale = context.locale.languageCode == 'fr' ? 'fr_FR' : 'en_US';
      return NumberFormat('#,##0.000', locale).format(amount);
    }

    final categoryInfo = categoriesInfo[detailedCagnotte.idCategorie] ?? categoriesInfo[1]!;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + bottomPadding + 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image principale de la cagnotte
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: double.infinity,
                height: isMobile ? 200 : 300,
                child: detailedCagnotte.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                  imageUrl: detailedCagnotte.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (_, _, _) => Icon(
                    categoryInfo.icon,
                    size: 80,
                    color: categoryInfo.color,
                  ),
                )
                    : Icon(
                  categoryInfo.icon,
                  size: 80,
                  color: categoryInfo.color,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Badge selon le type de cagnotte
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                decoration: BoxDecoration(
                  color: detailedCagnotte.isPermanente
                      ? const Color(0xFFfb8c00)
                      : Colors.green[300],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  detailedCagnotte.isPermanente
                      ? 'cagnotte_permanente_badge'.tr()
                      : 'cagnotte_ponctuelle_badge'.tr(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Carte de progression (seulement pour ponctuelle)
            if (!detailedCagnotte.isPermanente)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        getProgressLabel(detailedCagnotte.soldeCurrent),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFfb8c00),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'cagnotte_progress_label'.tr(
                          args: [
                            formatMoney(detailedCagnotte.soldeCurrent),
                            formatMoney(detailedCagnotte.objectifMonetaire),
                          ],
                        ),
                        child: LinearPercentIndicator(
                          percent: getProgress(detailedCagnotte.soldeCurrent),
                          lineHeight: 8,
                          backgroundColor: Colors.grey[300],
                          progressColor: const Color(0xFFfb8c00),
                          barRadius: const Radius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${formatMoneyGoal(detailedCagnotte.soldeCurrent)} € / ${formatMoney(detailedCagnotte.objectifMonetaire)} €',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1e88e5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'cagnotte_solde_collecte'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1e88e5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${formatMoneyGoal(detailedCagnotte.soldeCurrent)} €',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1e88e5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Bouton de don
            // Bouton de don et favori (dans la même carte)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    if (!detailedCagnotte.isPermanente && detailedCagnotte.soldeCurrent < detailedCagnotte.objectifMonetaire)
                      _buildDonateButton(isMobile)
                    else if (detailedCagnotte.isPermanente)
                      _buildDonateButton(isMobile)
                    else if (!detailedCagnotte.isPermanente && detailedCagnotte.soldeCurrent >= detailedCagnotte.objectifMonetaire)
                        Text(
                          'cagnotte_goal_reached'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1e88e5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                    const SizedBox(height: 12),
                    // Bouton favori
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFavorite ? Colors.red : Colors.grey,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      ),
                      icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, size: 20),
                      label: Text(_isFavorite ? 'cagnotte_remove_favorite'.tr() : 'cagnotte_add_favorite'.tr()),
                      onPressed: _isFavoriteLoading ? null : _toggleFavorite,
                    ),
                    const SizedBox(height: 12),
                    // Bouton Historique des paiements
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                      ),
                      icon: const Icon(Icons.receipt, size: 20),
                      label: Text('Historique des paiements'.tr()),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CagnottePaiementsScreen(cagnotteId: detailedCagnotte.id),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Association : logo en pleine largeur + nom centré (avec fallback icône)
            if (detailedCagnotte.association != null)
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/association',
                    arguments: {
                      'association': detailedCagnotte.association!,
                      'idCagnotte': detailedCagnotte.id,
                    },
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (detailedCagnotte.association!.logoUrl != null)
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          child: Container(
                            width: double.infinity,
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: CachedNetworkImage(
                              imageUrl: detailedCagnotte.association!.logoUrl!,
                              fit: BoxFit.contain,
                              placeholder: (_, _) => Container(
                                height: 150,
                                color: Colors.grey[200],
                                child: const Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (_, _, _) => Icon(
                                categoryInfo.icon,
                                size: 80,
                                color: categoryInfo.color,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          detailedCagnotte.association!.nom,
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width < 600 ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1e88e5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Description longue en HTML
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Text(
                        'cagnotte_project_description'.tr(),
                        style: TextStyle(
                          fontSize: isMobile ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1e88e5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Html(
                      data: detailedCagnotte.descriptionLongue,
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
                      onLinkTap: (url, attributes, element) async {
                        if (url != null) {
                          final uri = Uri.parse(url);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('error_unable_open_link'.tr())),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Semantics(
                  button: true,
                  label: 'cagnotte_share_label'.tr(args: [detailedCagnotte.titre]),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1e88e5),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    icon: const Icon(Icons.share, size: 20),
                    label: Text('cagnotte_share_button'.tr(), style: const TextStyle(fontSize: 14)),
                    onPressed: () async {
                      if (_shareData != null && _shareData!['text'] != null && _shareData!['url'] != null) {
                        final shareText = _shareData!['text'].toString().tr(
                          args: [detailedCagnotte.titre, _shareData!['url']],
                        );
                        await SharePlus.instance.share(ShareParams(text: shareText));
                      } else {
                        final url = 'https://www.1clic1don.fr/cagnotte.php?id=${detailedCagnotte.id}';
                        final shareText = 'cagnotte_share_text_2'.tr(args: [detailedCagnotte.titre, url]);
                        await SharePlus.instance.share(ShareParams(text: shareText));
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonateButton(bool isMobile) {
    return Semantics(
      button: true,
      label: 'cagnotte_donate_label'.tr(args: [detailedCagnotte.titre]),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF5733),
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, isMobile ? 50 : 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        icon: const Icon(Icons.card_giftcard, size: 20),
        label: Text('cagnotte_donate_button'.tr(), style: const TextStyle(fontSize: 14)),
        onPressed: () async {
          await Navigator.pushNamed(
            context,
            '/donate',
            arguments: DonationArgs(
              type: 'cagnotte',
              id: detailedCagnotte.id,
              libelle: detailedCagnotte.titre,
            ),
          );
          await _loadCagnotteDetails();
        },
      ),
    );
  }
}