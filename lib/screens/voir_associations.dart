import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:clic_1_don/models/association.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_menu.dart';
import 'package:clic_1_don/models/donation_args.dart';

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

class VoirAssociationsScreen extends StatefulWidget {
  const VoirAssociationsScreen({super.key});
  @override
  State<VoirAssociationsScreen> createState() => _VoirAssociationsScreenState();
}

class _VoirAssociationsScreenState extends State<VoirAssociationsScreen> {
  final _authService = AuthService();
  List<Map<String, dynamic>> associations = [];
  int totalAssociations = 0;
  int currentPage = 1;
  int perPage = 10;
  String libelleCategorie = '';
  bool isLoading = true;
  String errorMessage = '';
  int? categoryId;
  String? searchTerm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      setState(() {
        categoryId = args?['categoryId'] as int?;
        searchTerm = args?['schbox'] as String?;
        if (searchTerm != null) {
          libelleCategorie = 'voir_associations_search_results'.tr();
        } else if (categoryId != null && categories.containsKey(categoryId)) {
          libelleCategorie = categories[categoryId]!.nameKey.tr();
        } else {
          libelleCategorie = 'voir_associations_default_title'.tr();
        }
      });
      _loadAssociations();
    });
  }

  Future<void> _loadAssociations() async {
    try {
      String url = 'https://www.1clic1don.fr/app/voir_associations.php?page=$currentPage&perPage=$perPage';
      if (categoryId != null) {
        url += '&cat=$categoryId';
      }
      if (searchTerm != null) {
        url += '&schbox=${Uri.encodeQueryComponent(searchTerm!)}';
      }
      debugPrint('URL : $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('VoirAssociationsScreen: API response status: ${response.statusCode}');
      debugPrint('VoirAssociationsScreen: API response body: ${response.body}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('VoirAssociationsScreen: API parsed response: $data');
        if (data['success'] == true) {
          setState(() {
            associations = (data['associations'] as List<dynamic>)
                .map((item) => {
              'association': Association.fromJson(item),
              'id_categorie': item['id_categorie'] ?? 1,
              'partenaire': item['partenaire'] ?? 0,
            })
                .toList();
            totalAssociations = data['total'] as int? ?? 0;
            isLoading = false;
          });
        } else {
          throw Exception(data['message']?.tr() ?? 'error_unknown_api'.tr());
        }
      } else {
        throw Exception('error_loading'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('VoirAssociationsScreen: Error loading associations: $e');
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
      debugPrint('VoirAssociationsScreen: Token invalid, redirecting to /splash');
      Navigator.of(context).pushReplacementNamed('/splash');
    }
  }

  void _changePage(int page) {
    final totalPages = (totalAssociations / perPage).ceil();
    if (totalPages == 0 || page < 1 || page > totalPages) return;
    setState(() {
      currentPage = page;
      isLoading = true;
    });
    _loadAssociations();
  }

  void _changePerPage(int newPerPage) {
    setState(() {
      perPage = newPerPage;
      currentPage = 1;
      isLoading = true;
    });
    _loadAssociations();
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
        debugPrint('VoirAssociationsScreen: Back button pressed');
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            libelleCategorie,
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
              debugPrint('VoirAssociationsScreen: Leading hamburger button rendered');
              return IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  debugPrint('VoirAssociationsScreen: Hamburger button pressed');
                  Scaffold.of(context).openDrawer();
                },
                tooltip: 'welcome_menu_tooltip'.tr(),
              );
            },
          ),
        ),
        drawer: const AppMenu(currentRoute: '/voir-associations'),
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
            onPressed: _loadAssociations,
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
    if (associations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 60, color: Colors.blue),
            const SizedBox(height: 24),
            Text(
              'voir_associations_no_data'.tr(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'voir_associations_no_data_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/decouvrir-associations');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e88e5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              child: Text(
                'voir_associations_back_button'.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
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
        padding + bottomPadding + 40.0,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.star, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'voir_associations_favorites_note'.tr(),
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.sizeOf(context).width;
              final isMobile = screenWidth < 600;
              final cardWidth = isMobile ? screenWidth - 32 : (screenWidth - 48) / 2;
              return Wrap(
                spacing: 16.0,
                runSpacing: 16.0,
                children: associations
                    .asMap()
                    .entries
                    .map((entry) => SizedBox(
                  width: cardWidth,
                  child: _buildAssociationCard(entry.value),
                ))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 30),
          _buildPerPageSelector(),
          const SizedBox(height: 20),
          _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildAssociationCard(Map<String, dynamic> assocData) {
    final Association association = assocData['association'];
    final int idCategorie = assocData['id_categorie'] ?? 1;
    final bool isPartenaire = assocData['partenaire'] == 1;
    final category = categories[idCategorie] ?? categories[1]!;
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: InkWell(
        onTap: () => _navigateToDetail(association),
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(13),
            border: Border.all(color: Colors.grey.withAlpha(51)),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12.0)),
                child: Container(
                  height: 180,
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
                  child: association.logoUrl != null && association.logoUrl!.isNotEmpty
                      ? CachedNetworkImage(
                    imageUrl: association.logoUrl!,
                    httpHeaders: const {'Accept': 'image/*'},
                    placeholder: (_, _) => const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, _, _) => Icon(
                      category.icon,
                      size: 60,
                      color: category.color,
                    ),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  )
                      : Icon(
                    category.icon,
                    size: 60,
                    color: category.color,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isPartenaire) const Icon(Icons.star, color: Colors.orange, size: 20),
                        if (isPartenaire) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            association.nom == 'Association inconnue'
                                ? 'association_default_name'.tr()
                                : association.nom,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: category.color,
                              fontSize: isMobile ? 16 : 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      association.detailcourt ?? 'voir_associations_no_description'.tr(),
                      style: TextStyle(fontSize: isMobile ? 14 : 12),
                      maxLines: isMobile ? 4 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: category.color,
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        elevation: 2,
                        shadowColor: const Color.fromRGBO(0, 0, 0, 0.2),
                      ),
                      icon: const Icon(Icons.visibility, size: 20),
                      label: Text(
                        'welcome_button_details'.tr(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _navigateToDetail(association),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5733),
                        foregroundColor: Colors.white,
                        minimumSize: Size(double.infinity, isMobile ? 50 : 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        elevation: 2,
                        shadowColor: const Color.fromRGBO(0, 0, 0, 0.2),
                      ),
                      icon: const Icon(Icons.card_giftcard, size: 20, color: Colors.white),
                      label: Text(
                        'welcome_button_donate'.tr(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (mounted) {
                          Navigator.pushNamed(
                            context,
                            '/donate',
                            arguments: DonationArgs(
                              type: 'association',
                              id: association.id,
                              libelle: association.nom == 'Association inconnue'
                                  ? 'association_default_name'.tr()
                                  : association.nom,
                            ),
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
      ),
    );
  }

  Widget _buildPerPageSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'voir_associations_per_page'.tr(),
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
        const SizedBox(width: 10),
        DropdownButton<int>(
          value: perPage,
          items: const [
            DropdownMenuItem(value: 10, child: Text('10')),
            DropdownMenuItem(value: 20, child: Text('20')),
            DropdownMenuItem(value: 50, child: Text('50')),
          ],
          onChanged: (value) {
            if (value != null) {
              _changePerPage(value);
            }
          },
          style: const TextStyle(fontSize: 16, color: Colors.black87),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(4.0),
        ),
      ],
    );
  }

  Widget _buildPagination() {
    final int safeTotalPages = (totalAssociations / perPage).ceil();
    if (safeTotalPages == 0) {
      return const SizedBox.shrink();
    }

    const int maxPagesToShow = 2;
    final int totalPages = safeTotalPages;

    final int maxStart = totalPages - maxPagesToShow + 1;
    final int safeMaxStart = maxStart > 0 ? maxStart : 1;

    final int rawStart = currentPage - (maxPagesToShow ~/ 2);
    final int start = rawStart.clamp(1, safeMaxStart);
    final int end = (start + maxPagesToShow - 1).clamp(start, totalPages);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.8),
        borderRadius: BorderRadius.circular(8.0),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.1),
            blurRadius: 4.0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (currentPage > 1) ...[
            IconButton(
              icon: const Icon(Icons.first_page),
              iconSize: 20.0,
              onPressed: () => _changePage(1),
              color: Colors.orange,
              tooltip: 'voir_associations_first_page'.tr(),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              iconSize: 20.0,
              onPressed: () => _changePage(currentPage - 1),
              color: Colors.orange,
              tooltip: 'voir_associations_previous_page'.tr(),
            ),
          ],
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (start > 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text('...', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ),
                  for (int i = start; i <= end; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ElevatedButton(
                        onPressed: () => _changePage(i),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: i == currentPage ? Colors.blue : Colors.orange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(28, 28),
                          padding: const EdgeInsets.all(6.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                        child: Text('$i', style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                  if (end < totalPages)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text('...', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ),
          if (currentPage < totalPages) ...[
            IconButton(
              icon: const Icon(Icons.chevron_right),
              iconSize: 20.0,
              onPressed: () => _changePage(currentPage + 1),
              color: Colors.orange,
              tooltip: 'voir_associations_next_page'.tr(),
            ),
            IconButton(
              icon: const Icon(Icons.last_page),
              iconSize: 20.0,
              onPressed: () => _changePage(totalPages),
              color: Colors.orange,
              tooltip: 'voir_associations_last_page'.tr(),
            ),
          ],
        ],
      ),
    );
  }

  void _navigateToDetail(Association association) {
    if (mounted) {
      Navigator.pushNamed(
        context,
        '/association',
        arguments: association,
      );
    }
  }
}