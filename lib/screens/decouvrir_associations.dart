import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_menu.dart';

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

// Modèle pour une catégorie d'association
class AssociationCategory {
  final int id;
  final String libelleCategorie;
  final int countasso;
  AssociationCategory({
    required this.id,
    required this.libelleCategorie,
    required this.countasso,
  });

  factory AssociationCategory.fromJson(Map<String, dynamic> json) {
    final apiLibelle = json['libelle_categorie'] as String;
    final categoryKey = {
      'ANIMAUX': 'category_animals',
      'ENVIRONNEMENT': 'category_environment',
      'HUMANITAIRE': 'category_humanitarian',
      'MÉDIAS & CULTURE': 'category_media_culture',
    }[apiLibelle];
    return AssociationCategory(
      id: json['id'] as int,
      libelleCategorie: categoryKey != null ? categoryKey.tr() : apiLibelle,
      countasso: json['countasso'] as int,
    );
  }
}

class DecouvrirAssociationsScreen extends StatefulWidget {
  const DecouvrirAssociationsScreen({super.key});
  @override
  State<DecouvrirAssociationsScreen> createState() => _DecouvrirAssociationsScreenState();
}

class _DecouvrirAssociationsScreenState extends State<DecouvrirAssociationsScreen> {
  final _authService = AuthService();
  List<AssociationCategory> associationCategories = [];
  bool isLoading = true;
  String errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadAssociationCategories();
  }

  Future<void> _loadAssociationCategories() async {
    try {
      final response = await http.get(Uri.parse('https://www.1clic1don.fr/app/liste_associations.php'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            associationCategories = (data['categories'] as List<dynamic>)
                .map((item) => AssociationCategory.fromJson(item as Map<String, dynamic>))
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
      debugPrint('DecouvrirAssociationsScreen: Error loading associations: $e');
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
      debugPrint('DecouvrirAssociationsScreen: Token invalid, redirecting to /splash');
      Navigator.of(context).pushReplacementNamed('/splash');
    }
  }

  void _searchAssociations() {
    if (_formKey.currentState!.validate()) {
      final query = _searchController.text.trim();
      if (mounted) {
        Navigator.pushNamed(
          context,
          '/voir-associations',
          arguments: {'schbox': query},
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600; // Détermine si c'est un mobile
    final double padding = isMobile ? 8.0 : 12.0; // Padding dynamique
    final double bottomPadding = MediaQuery.of(context).padding.bottom; // Padding système

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        debugPrint('DecouvrirAssociationsScreen: Back button pressed');
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'decouvrir_associations_title'.tr(),
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
              debugPrint('DecouvrirAssociationsScreen: Leading hamburger button rendered');
              return IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  debugPrint('DecouvrirAssociationsScreen: Hamburger button pressed');
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
                const url = 'https://www.1clic1don.fr/decouvrir-associations.php';
                final shareText = 'decouvrir_associations_share_text'.tr(args: [url]);
                await SharePlus.instance.share(ShareParams(text: shareText));
              },
            ),
          ],
        ),
        drawer: const AppMenu(currentRoute: '/decouvrir-associations'),
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
                : _buildContent(padding, isMobile, bottomPadding),
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
            onPressed: _loadAssociationCategories,
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

  Widget _buildContent(double padding, bool isMobile, double bottomPadding) {
    if (associationCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 50, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              'decouvrir_associations_no_data'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'decouvrir_associations_no_data_subtitle'.tr(),
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
        padding + bottomPadding + 40.0, // Padding dynamique + 40px comme dans CagnotteDetailScreen
      ),
      child: Column(
        children: [
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
                  'decouvrir_associations_search_title'.tr(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Form(
                  key: _formKey,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'decouvrir_associations_search_hint'.tr(),
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
                              return 'decouvrir_associations_search_validation'.tr();
                            }
                            return null;
                          },
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _searchAssociations,
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
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.grey[600]!, width: 5.0),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.groups, color: Colors.grey[600]),
                const SizedBox(width: 10),
                Text(
                  'decouvrir_associations_categories_title'.tr(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.sizeOf(context).width;
              final isMobile = screenWidth < 600;
              final cardWidth = isMobile ? screenWidth - 32 : (screenWidth - 48) / 2;
              return Wrap(
                spacing: 16.0,
                runSpacing: 16.0,
                children: associationCategories
                    .asMap()
                    .entries
                    .map((entry) => SizedBox(
                  width: cardWidth,
                  child: _buildCategoryCard(associationCategories[entry.key]),
                ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (mounted) {
                Navigator.pushNamed(context, '/voir-associations');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[600],
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: Text(
              'decouvrir_associations_all_button'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(AssociationCategory category) {
    final cat = categories[category.id] ?? categories[1]!;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        onTap: () {
          if (mounted) {
            Navigator.pushNamed(
              context,
              '/voir-associations',
              arguments: {'categoryId': category.id},
            );
          }
        },
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(13),
            border: Border.all(color: Colors.grey.withAlpha(51)),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(cat.icon, color: cat.color, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.libelleCategorie,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cat.color,
                        fontSize: isMobile ? 16 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'decouvrir_associations_count'.tr(args: [category.countasso.toString()]),
                style: TextStyle(fontSize: isMobile ? 14 : 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cat.color,
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
                      '/voir-associations',
                      arguments: {'categoryId': category.id},
                    );
                  }
                },
                child: Text(
                  'decouvrir_associations_category_button'.tr(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}