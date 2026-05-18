import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'cagnotte.dart';
import 'app_menu.dart';
import 'cagnotte_category_screen.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:clic_1_don/models/donation_args.dart';
import 'package:flutter/scheduler.dart';

// Définir les catégories avec clés traduites
const Map<int, Category> categories = {
  1: Category('category_animals', Colors.blue, Icons.pets),
  2: Category('category_environment', Colors.green, Icons.eco),
  3: Category('category_humanitarian', Colors.orange, Icons.volunteer_activism),
  4: Category('category_media_culture', Colors.purple, Icons.movie),
};

// Classe Category immutable
class Category {
  final String nameKey;
  final Color color;
  final IconData icon;
  const Category(this.nameKey, this.color, this.icon);
}

class CagnotteListScreen extends StatefulWidget {
  const CagnotteListScreen({super.key});
  @override
  State<CagnotteListScreen> createState() => _CagnotteListScreenState();
}

class _CagnotteListScreenState extends State<CagnotteListScreen> {
  final AuthService _authService = AuthService();
  List<Cagnotte> cagnottes = [];
  bool isLoading = true;
  String errorMessage = '';

  // Contrôleurs pour la recherche
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<FormState> _searchFormKey = GlobalKey<FormState>();

  // Limite d'affichage par catégorie
  int get _maxPerCategory {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth < 600 ? 2 : 6;
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadCagnottes();
    });
  }

  Future<void> _loadCagnottes() async {
    try {
      final String lang = context.locale.languageCode;
      final response = await http.get(
        Uri.parse('https://www.1clic1don.fr/app/liste_cagnottes.php?lang=$lang'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            cagnottes = (data['projets'] as List<dynamic>)
                .map((item) => Cagnotte.fromJson(item as Map<String, dynamic>))
                .toList();
            isLoading = false;
          });
        } else {
          throw Exception(data['message']?.tr() ?? 'error_unknown_api'.tr());
        }
      } else {
        throw Exception('error_loading'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('CagnotteListScreen: Error loading cagnottes: $e');
      if (mounted) {
        setState(() {
          errorMessage = 'error_technical_difficulties'.tr();
          isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePop() async {
    final isValid = await _authService.isTokenValid();
    if (!mounted) return;
    if (!isValid) {
      debugPrint('CagnotteListScreen: Token invalid, redirecting to /splash');
      Navigator.of(context).pushReplacementNamed('/splash');
    }
  }

  void _searchCagnottes() {
    if (_searchFormKey.currentState!.validate()) {
      final query = _searchController.text.trim();
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/recherche-cagnottes',
          arguments: query,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('CagnotteListScreen: Rendering AppBar with leading hamburger');
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        debugPrint('CagnotteListScreen: Back button pressed');
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'cagnotte_list_title'.tr(),
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
              debugPrint('CagnotteListScreen: Leading hamburger button rendered');
              return IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  debugPrint('CagnotteListScreen: Hamburger button pressed');
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
                const url = 'https://www.1clic1don.fr/liste-cagnottes.php';
                final shareText = 'cagnotte_list_share_text'.tr(args: [url]);
                await SharePlus.instance.share(ShareParams(text: shareText));
              },
            ),
          ],
        ),
        drawer: const AppMenu(currentRoute: '/liste-cagnottes'),
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
              : errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : _buildContent(),
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
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadCagnottes,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5733),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: Text('error_retry_button'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final double padding = MediaQuery.of(context).size.width < 600 ? 8.0 : 12.0;

    if (cagnottes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 50, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              'cagnotte_list_no_data'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'cagnotte_list_no_data_subtitle'.tr(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        padding,
        padding,
        padding,
        padding + bottomPadding + 16.0,
      ),
      child: Column(
        children: [
          // Bloc de recherche
          Container(
            padding: const EdgeInsets.all(20.0),
            margin: const EdgeInsets.only(bottom: 30.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE9ECEF), Color(0xFFDEE2E6)],
              ),
              borderRadius: BorderRadius.circular(12.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(26),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'cagnotte_search_title'.tr(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Form(
                  key: _searchFormKey,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'cagnotte_search_hint'.tr(),
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(8.0),
                                bottomLeft: Radius.circular(8.0),
                              ),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 2) {
                              return 'cagnotte_search_validation'.tr();
                            }
                            return null;
                          },
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _searchCagnottes,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8.0),
                              bottomRight: Radius.circular(8.0),
                            ),
                          ),
                          minimumSize: const Size(60, 48),
                        ),
                        child: const Icon(Icons.search, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Le reste de la liste catégorisée
          ..._buildCategorizedCagnottes(),
        ],
      ),
    );
  }

  List<Widget> _buildCategorizedCagnottes() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final maxPerCat = _maxPerCategory;

    return categories.entries.map((entry) {
      final categoryCagnottes = cagnottes.where((c) => c.idCategorie == entry.key).toList();
      if (categoryCagnottes.isEmpty) return const SizedBox.shrink();

      final displayed = categoryCagnottes.take(maxPerCat).toList();
      final hasMore = categoryCagnottes.length > maxPerCat;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: entry.value.color, width: 5.0),
              ),
            ),
            child: Row(
              children: [
                Icon(entry.value.icon, color: entry.value.color),
                const SizedBox(width: 10),
                Text(
                  entry.value.nameKey.tr(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: entry.value.color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = isMobile ? screenWidth - 32 : (screenWidth - 48) / 2;
              return Wrap(
                spacing: 16.0,
                runSpacing: 16.0,
                children: displayed.map((cagnotte) => SizedBox(
                  width: cardWidth,
                  child: _buildCagnotteCard(cagnotte),
                )).toList(),
              );
            },
          ),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CagnotteCategoryScreen(
                          categoryId: entry.key,
                          categoryName: entry.value.nameKey.tr(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.view_list, size: 20),
                  label: Text('cagnotte_list_see_all'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: entry.value.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 40),
        ],
      );
    }).toList();
  }

  Widget _buildCagnotteCard(Cagnotte cagnotte) {
    final category = categories[cagnotte.idCategorie] ?? categories[1]!;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(cagnotte),
        borderRadius: BorderRadius.circular(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12.0)),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth;
                  const aspectRatio = 4 / 3;
                  final imageHeight = cardWidth / aspectRatio;
                  return SizedBox(
                    height: imageHeight,
                    child: cagnotte.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                      imageUrl: cagnotte.imageUrl,
                      httpHeaders: const {'Accept': 'image/*'},
                      placeholder: (_, _) => Container(
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, _, _) => Icon(
                        category.icon,
                        size: 60,
                        color: category.color,
                      ),
                      fit: BoxFit.cover,
                    )
                        : Icon(
                      category.icon,
                      size: 60,
                      color: category.color,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cagnotte.isPermanente)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFfb8c00),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'cagnotte_permanente_badge'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (!cagnotte.isPermanente)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'cagnotte_ponctuelle_badge'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  Text(
                    cagnotte.titre,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: category.color,
                      fontSize: isMobile ? 14 : 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cagnotte.descriptionCourte,
                    style: TextStyle(fontSize: isMobile ? 12 : 10),
                    maxLines: isMobile ? 4 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: category.color,
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    ),
                    icon: const Icon(Icons.visibility, size: 20),
                    label: Text('cagnotte_list_details_button'.tr()),
                    onPressed: () => _navigateToDetail(cagnotte),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5733),
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    ),
                    icon: const Icon(Icons.card_giftcard, size: 20),
                    label: Text('cagnotte_list_donate_button'.tr()),
                    onPressed: () {
                      if (mounted) {
                        Navigator.pushNamed(
                          context,
                          '/donate',
                          arguments: DonationArgs(type: 'cagnotte', id: cagnotte.id, libelle: cagnotte.titre),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(Cagnotte cagnotte) {
    if (mounted) {
      Navigator.pushNamed(
        context,
        '/cagnotte',
        arguments: cagnotte,
      );
    }
  }
}