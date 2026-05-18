import 'package:flutter/material.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:clic_1_don/screens/cagnotte.dart';
import 'package:clic_1_don/models/donation_args.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';

// Catégories (identique à liste_cagnottes)
const Map<int, Category> categories = {
  1: Category('category_animals', Color(0xFF1e88e5), Icons.pets),
  2: Category('category_environment', Color(0xFF689f38), Icons.eco),
  3: Category('category_humanitarian', Color(0xFFfb8c00), Icons.volunteer_activism),
  4: Category('category_media_culture', Color(0xFF9c27b0), Icons.movie),
};

class Category {
  final String nameKey;
  final Color color;
  final IconData icon;
  const Category(this.nameKey, this.color, this.icon);
}

class MesFavorisCagnottesScreen extends StatefulWidget {
  const MesFavorisCagnottesScreen({super.key});

  @override
  State<MesFavorisCagnottesScreen> createState() => _MesFavorisCagnottesScreenState();
}

class _MesFavorisCagnottesScreenState extends State<MesFavorisCagnottesScreen> {
  final AuthService _authService = AuthService();
  List<String> _favoriteIds = [];
  List<Cagnotte> _cagnottes = [];
  bool _isLoading = true;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = await _authService.isTokenValid();
    List<String> ids = [];

    if (isLoggedIn) {
      final memberId = await _authService.getMemberId();
      if (memberId != null) {
        try {
          final response = await http.get(
            Uri.parse('https://www.1clic1don.fr/app/list_favorites.php?type=cagnotte&member_id=$memberId'),
          );
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true) {
              ids = (data['ids'] as List).map((e) => e.toString()).toList();
              // Met à jour le stockage local avec la liste serveur
              await prefs.setStringList('favorites_cagnottes', ids);
            } else {
              // Erreur API -> on utilise le local
              ids = prefs.getStringList('favorites_cagnottes') ?? [];
            }
          } else {
            ids = prefs.getStringList('favorites_cagnottes') ?? [];
          }
        } catch (e) {
          debugPrint('Erreur chargement favoris cagnottes depuis serveur: $e');
          ids = prefs.getStringList('favorites_cagnottes') ?? [];
        }
      } else {
        ids = prefs.getStringList('favorites_cagnottes') ?? [];
      }
    } else {
      ids = prefs.getStringList('favorites_cagnottes') ?? [];
    }

    setState(() {
      _favoriteIds = ids;
    });
    await _fetchCagnottesDetails();
  }

  Future<void> _fetchCagnottesDetails() async {
    if (_favoriteIds.isEmpty) {
      if (mounted) {
        setState(() {
        _cagnottes = [];
        _isLoading = false;
      });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    final lang = context.locale.languageCode;
    final fetched = <Cagnotte>[];

    for (final idStr in _favoriteIds) {
      final id = int.tryParse(idStr) ?? 0;
      if (id == 0) continue;
      try {
        final response = await http.get(
          Uri.parse('https://www.1clic1don.fr/app/cagnotte.php?id=$id&lang=$lang'),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            fetched.add(Cagnotte.fromJson({
              ...data['projet'],
              'association': data['association'],
            }));
          }
        }
      } catch (e) {
        debugPrint('Erreur chargement cagnotte $id : $e');
      }
    }

    if (mounted) {
      setState(() {
        _cagnottes = fetched;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeFromFavorites(int cagnotteId) async {
    if (_isRemoving) return;
    setState(() => _isRemoving = true);

    final isLoggedIn = await _authService.isTokenValid();

    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedIds = _favoriteIds.where((id) => id != cagnotteId.toString()).toList();
      await prefs.setStringList('favorites_cagnottes', updatedIds);

      if (mounted) {
        setState(() {
          _favoriteIds = updatedIds;
          _cagnottes.removeWhere((c) => c.id == cagnotteId);
        });
      }

      if (isLoggedIn) {
        final memberId = await _authService.getMemberId();
        if (memberId != null) {
          await http.post(
            Uri.parse('https://www.1clic1don.fr/app/ajax-favori.php'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'type': 'cagnotte',
              'id': cagnotteId,
              'action': 'remove',
              'member_id': memberId,
            }),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('cagnotte_removed_favorite'.tr())),
        );
      }
    } catch (e) {
      debugPrint('Erreur suppression favori cagnotte: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('error_favorite_action'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _isRemoving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('mes_cagnottes_favorites_title'.tr()),
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
            : _cagnottes.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite, size: 80, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'aucun_favori_cagnotte'.tr(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/liste-cagnottes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFfb8c00),
                  foregroundColor: Colors.white,
                ),
                child: Text('decouvrir_cagnottes'.tr()),
              ),
            ],
          ),
        )
            : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _cagnottes.length,
          itemBuilder: (context, index) =>
              _buildCagnotteCard(_cagnottes[index], isMobile),
        ),
      ),
    );
  }

  Widget _buildCagnotteCard(Cagnotte cagnotte, bool isMobile) {
    final category = categories[cagnotte.idCategorie] ?? categories[1]!;

    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        onTap: () => _navigateToDetail(cagnotte),
        borderRadius: BorderRadius.circular(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
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
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(230), // au lieu de withOpacity
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(51), // 0.2 * 255 ≈ 51
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.red, size: 20),
                      onPressed: _isRemoving ? null : () => _removeFromFavorites(cagnotte.id),
                      tooltip: 'retirer_des_favoris'.tr(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ),
                ),
              ],
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
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                    onPressed: () => _navigateToDon(cagnotte),
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
    Navigator.pushNamed(context, '/cagnotte', arguments: cagnotte);
  }

  void _navigateToDon(Cagnotte cagnotte) {
    Navigator.pushNamed(
      context,
      '/donate',
      arguments: DonationArgs(type: 'cagnotte', id: cagnotte.id, libelle: cagnotte.titre),
    );
  }
}