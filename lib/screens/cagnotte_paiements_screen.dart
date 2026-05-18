import 'package:flutter/material.dart';
import 'package:clic_1_don/models/paiement_cagnotte.dart';
import 'package:clic_1_don/models/pagination_response.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CagnottePaiementsScreen extends StatefulWidget {
  final int cagnotteId;
  const CagnottePaiementsScreen({super.key, required this.cagnotteId});

  @override
  State<CagnottePaiementsScreen> createState() => _CagnottePaiementsScreenState();
}

class _CagnottePaiementsScreenState extends State<CagnottePaiementsScreen> {
  late Future<PaginatedResponse<PaiementCagnotte>> _futurePaiements;
  int _currentPage = 1;
  final int _limit = 10;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  void _loadPage() {
    setState(() {
      _futurePaiements = fetchPaiementsCagnotte(widget.cagnotteId, page: _currentPage, limit: _limit);
    });
  }

  void _goToPage(int page) {
    if (page < 1) return;
    setState(() {
      _currentPage = page;
      _loadPage();
    });
  }

  Future<PaginatedResponse<PaiementCagnotte>> fetchPaiementsCagnotte(
      int cagnotteId, {
        int page = 1,
        int limit = 10,
      }) async {
    final response = await http.get(
      Uri.parse('https://www.1clic1don.fr/app/api_cagnotte_paiements.php?id=$cagnotteId&page=$page&limit=$limit'),
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        final List list = json['data'];
        final items = list.map((item) => PaiementCagnotte.fromJson(item)).toList();
        final pag = json['pagination'];
        return PaginatedResponse(
          data: items,
          currentPage: pag['currentPage'],
          totalPages: pag['totalPages'],
          totalItems: pag['totalItems'],
          limit: pag['limit'],
        );
      } else {
        throw Exception(json['message'] ?? 'Erreur');
      }
    } else {
      throw Exception('Erreur HTTP ${response.statusCode}');
    }
  }

  void _showPreuves(List<Preuve> preuves) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Preuves'.tr()),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: preuves.length,
            itemBuilder: (context, index) {
              final preuve = preuves[index];
              final isImage = preuve.fichier.toLowerCase().endsWith('.jpg') ||
                  preuve.fichier.toLowerCase().endsWith('.jpeg') ||
                  preuve.fichier.toLowerCase().endsWith('.png') ||
                  preuve.fichier.toLowerCase().endsWith('.gif') ||
                  preuve.fichier.toLowerCase().endsWith('.webp');
              return ListTile(
                leading: Icon(isImage ? Icons.image : Icons.picture_as_pdf),
                title: Text(preuve.fichier.split('/').last),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(preuve.dateUpload)),
                onTap: () async {
                  final url = preuve.fichier.startsWith('http')
                      ? preuve.fichier
                      : 'https://www.1clic1don.fr/${preuve.fichier}';
                  if (await canLaunchUrl(Uri.parse(url))) {
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Fermer'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Demandes de paiement'.tr()),
        backgroundColor: const Color(0xFF1e88e5),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: FutureBuilder<PaginatedResponse<PaiementCagnotte>>(
        future: _futurePaiements,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.data.isEmpty) {
            return Center(child: Text('Aucune demande de paiement'.tr()));
          }

          final response = snapshot.data!;
          final paiements = response.data;
          final totalPages = response.totalPages;
          final currentPage = response.currentPage;

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: paiements.length,
                  itemBuilder: (context, index) {
                    final p = paiements[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text('${p.montant.toStringAsFixed(2)} €'),
                        subtitle: Text(DateFormat('dd/MM/yyyy').format(p.dateDemande)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Preuves : ${p.preuves.length}'.tr()),
                                const SizedBox(height: 8),
                                if (p.preuves.isNotEmpty)
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.visibility),
                                    label: Text('Voir les preuves'.tr()),
                                    onPressed: () => _showPreuves(p.preuves),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (totalPages > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: currentPage > 1 ? () => _goToPage(currentPage - 1) : null,
                      ),
                      ...List.generate(totalPages, (index) {
                        final pageNum = index + 1;
                        if (pageNum == 1 || pageNum == totalPages || (pageNum >= currentPage - 2 && pageNum <= currentPage + 2)) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: currentPage == pageNum ? Colors.blue : Colors.grey[300],
                                foregroundColor: currentPage == pageNum ? Colors.white : Colors.black,
                              ),
                              onPressed: () => _goToPage(pageNum),
                              child: Text(pageNum.toString()),
                            ),
                          );
                        } else if ((pageNum == currentPage - 3 && currentPage > 3) ||
                            (pageNum == currentPage + 3 && currentPage < totalPages - 2)) {
                          return const Text(' ... ');
                        } else {
                          return const SizedBox.shrink();
                        }
                      }),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: currentPage < totalPages ? () => _goToPage(currentPage + 1) : null,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}