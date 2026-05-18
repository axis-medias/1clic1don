import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'cagnotte.dart';
import 'package:clic_1_don/models/donation_args.dart';

// Catégories communes (identique à celle de CagnotteCategoryScreen)
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

class RechercheCagnottesScreen extends StatefulWidget {
  final String searchTerm;
  const RechercheCagnottesScreen({super.key, required this.searchTerm});

  @override
  State<RechercheCagnottesScreen> createState() => _RechercheCagnottesScreenState();
}

class _RechercheCagnottesScreenState extends State<RechercheCagnottesScreen> {
  List<Cagnotte> _cagnottes = [];
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  final int _limit = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCagnottes();
    });
  }

  Future<void> _loadCagnottes() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final lang = context.locale.languageCode;
      final url = Uri.parse(
        'https://www.1clic1don.fr/app/recherche_cagnottes.php'
            '?search=${Uri.encodeComponent(widget.searchTerm)}&lang=$lang&page=$_currentPage&limit=$_limit',
      );
      final response = await http.get(url);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _cagnottes = (data['projets'] as List<dynamic>)
                .map((item) => Cagnotte.fromJson(item as Map<String, dynamic>))
                .toList();
            final total = data['total'] as int;
            _totalPages = (total / _limit).ceil();
            _isLoading = false;
          });
        } else {
          throw Exception(data['message']?.tr() ?? 'error_unknown_api'.tr());
        }
      } else {
        throw Exception('error_loading'.tr(args: [response.statusCode.toString()]));
      }
    } catch (e) {
      debugPrint('RechercheCagnottesScreen: error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur : ${e.toString()}';
          _isLoading = false;
          _isError = true;
        });
      }
    }
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages) return;
    setState(() {
      _currentPage = page;
    });
    _loadCagnottes();
  }

  String _formatMoney(double amount) {
    final locale = context.locale.languageCode == 'fr' ? 'fr_FR' : 'en_US';
    return NumberFormat('#,##0.000', locale).format(amount);
  }

  String _formatMoney2(double amount) {
    final locale = context.locale.languageCode == 'fr' ? 'fr_FR' : 'en_US';
    return NumberFormat('#,##0.00', locale).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('cagnotte_search_results_title'.tr(namedArgs: {'search': widget.searchTerm})),
        backgroundColor: const Color(0xFF1e88e5),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isError
            ? _buildErrorWidget()
            : _buildContent(),
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
          Text(_errorMessage, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadCagnottes,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5733),
              foregroundColor: Colors.white,
            ),
            child: Text('error_retry_button'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_cagnottes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 50, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              'cagnotte_search_no_result'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomPadding + 20),
      child: Column(
        children: [
          if (isMobile)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _cagnottes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildCagnotteMobileCard(_cagnottes[index]),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 320,
              ),
              itemCount: _cagnottes.length,
              itemBuilder: (context, index) => _buildCagnotteDesktopCard(_cagnottes[index]),
            ),
          const SizedBox(height: 20),
          if (_totalPages > 1) _buildPagination(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Carte pour mobile (affichage horizontal)
  Widget _buildCagnotteMobileCard(Cagnotte cagnotte) {
    final categoryInfo = categoriesInfo[cagnotte.idCategorie] ?? categoriesInfo[1]!;
    final categoryColor = categoryInfo.color;
    final categoryIcon = categoryInfo.icon;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _navigateToDetail(cagnotte),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: SizedBox(
                width: 120,
                height: 160,
                child: cagnotte.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                  imageUrl: cagnotte.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey[200]),
                  errorWidget: (_, _, _) => Icon(
                    categoryIcon,
                    size: 60,
                    color: categoryColor,
                  ),
                )
                    : Icon(
                  categoryIcon,
                  size: 60,
                  color: categoryColor,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cagnotte.isPermanente
                            ? const Color(0xFFfb8c00)
                            : Colors.green[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        cagnotte.isPermanente
                            ? 'cagnotte_permanente_badge'.tr()
                            : 'cagnotte_ponctuelle_badge'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Text(
                      cagnotte.titre,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: categoryColor,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cagnotte.descriptionCourte,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Affichage du solde
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            'cagnotte_solde_title'.tr(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatMoney(cagnotte.soldeCurrent)} €',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold, color: categoryColor),
                          ),
                          if (!cagnotte.isPermanente)
                            Text(
                              ' / ${_formatMoney2(cagnotte.objectifMonetaire)} €',
                              style: const TextStyle(fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: categoryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            icon: const Icon(Icons.visibility, size: 14),
                            label: Text(
                              'cagnotte_list_details_button'.tr(),
                              style: const TextStyle(fontSize: 10),
                            ),
                            onPressed: () => _navigateToDetail(cagnotte),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF5733),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            icon: const Icon(Icons.card_giftcard, size: 14),
                            label: Text(
                              'cagnotte_list_donate_button'.tr(),
                              style: const TextStyle(fontSize: 10),
                            ),
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/donate',
                                arguments: DonationArgs(
                                  type: 'cagnotte',
                                  id: cagnotte.id,
                                  libelle: cagnotte.titre,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Carte pour tablette / desktop (affichage vertical)
  Widget _buildCagnotteDesktopCard(Cagnotte cagnotte) {
    final categoryInfo = categoriesInfo[cagnotte.idCategorie] ?? categoriesInfo[1]!;
    final categoryColor = categoryInfo.color;
    final categoryIcon = categoryInfo.icon;
    const double imageHeight = 140.0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _navigateToDetail(cagnotte),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: cagnotte.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                  imageUrl: cagnotte.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.grey[200]),
                  errorWidget: (_, _, _) => Icon(
                    categoryIcon,
                    size: 60,
                    color: categoryColor,
                  ),
                )
                    : Icon(
                  categoryIcon,
                  size: 60,
                  color: categoryColor,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cagnotte.isPermanente
                              ? const Color(0xFFfb8c00)
                              : Colors.green[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          cagnotte.isPermanente
                              ? 'cagnotte_permanente_badge'.tr()
                              : 'cagnotte_ponctuelle_badge'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      cagnotte.titre,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: categoryColor,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Text(
                        cagnotte.descriptionCourte,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Bloc solde (vertical)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'cagnotte_solde_title'.tr(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatMoney(cagnotte.soldeCurrent)} €',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: categoryColor,
                            ),
                          ),
                          if (!cagnotte.isPermanente)
                            Text(
                              '/ ${_formatMoney2(cagnotte.objectifMonetaire)} €',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: categoryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      ),
                      icon: const Icon(Icons.visibility, size: 14),
                      label: Text(
                        'cagnotte_list_details_button'.tr(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      onPressed: () => _navigateToDetail(cagnotte),
                    ),
                    const SizedBox(height: 4),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF5733),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      ),
                      icon: const Icon(Icons.card_giftcard, size: 14),
                      label: Text(
                        'cagnotte_list_donate_button'.tr(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          '/donate',
                          arguments: DonationArgs(
                            type: 'cagnotte',
                            id: cagnotte.id,
                            libelle: cagnotte.titre,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagination() {
    const int maxVisible = 3;
    int total = _totalPages;
    int current = _currentPage;
    List<int> pages = [];

    if (total <= maxVisible) {
      pages = List.generate(total, (i) => i + 1);
    } else {
      int start = (current - 2).clamp(1, total - maxVisible + 1);
      int end = (start + maxVisible - 1).clamp(1, total);
      pages = List.generate(end - start + 1, (i) => start + i);

      if (!pages.contains(1)) {
        pages.insert(0, 1);
        if (pages[1] != 2) pages.insert(1, -1);
      }
      if (!pages.contains(total)) {
        if (pages.last != total - 1) pages.add(-1);
        pages.add(total);
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: current > 1 ? () => _goToPage(current - 1) : null,
        ),
        ...pages.map((pageNum) {
          if (pageNum == -1) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('...'),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: pageNum == current
                ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1e88e5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$pageNum',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
                : InkWell(
              onTap: () => _goToPage(pageNum),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('$pageNum'),
              ),
            ),
          );
        }),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: current < total ? () => _goToPage(current + 1) : null,
        ),
      ],
    );
  }

  void _navigateToDetail(Cagnotte cagnotte) {
    Navigator.pushNamed(context, '/cagnotte', arguments: cagnotte);
  }
}