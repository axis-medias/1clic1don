import 'package:flutter/material.dart';
import 'package:clic_1_don/models/paiement_association.dart';
import 'package:clic_1_don/models/pagination_response.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AssociationPaiementsScreen extends StatefulWidget {
  final int associationId;
  const AssociationPaiementsScreen({super.key, required this.associationId});

  @override
  State<AssociationPaiementsScreen> createState() => _AssociationPaiementsScreenState();
}

class _AssociationPaiementsScreenState extends State<AssociationPaiementsScreen> {
  late Future<PaginatedResponse<PaiementAssociation>> _futurePaiements;
  int _currentPage = 1;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  void _loadPage() {
    setState(() {
      _futurePaiements = fetchPaiementsAssociation(widget.associationId, page: _currentPage, limit: _limit);
    });
  }

  void _goToPage(int page) {
    if (page < 1) return;
    setState(() {
      _currentPage = page;
      _loadPage();
    });
  }

  Future<PaginatedResponse<PaiementAssociation>> fetchPaiementsAssociation(
      int associationId, {
        int page = 1,
        int limit = 20,
      }) async {
    final response = await http.get(
      Uri.parse('https://www.1clic1don.fr/app/api_asso_paiements.php?id=$associationId&page=$page&limit=$limit'),
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      if (json['success'] == true) {
        final List list = json['data'];
        final items = list.map((item) => PaiementAssociation.fromJson(item)).toList();
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('Historique des paiements'.tr()),
        backgroundColor: const Color(0xFF1e88e5),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: FutureBuilder<PaginatedResponse<PaiementAssociation>>(
        future: _futurePaiements,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.data.isEmpty) {
            return Center(child: Text('Aucun paiement enregistré'.tr()));
          }

          final response = snapshot.data!;
          final paiements = response.data;
          final totalPages = response.totalPages;
          final currentPage = response.currentPage;

          return Column(
            children: [
              // Tableau des paiements
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Table(
                      border: TableBorder.all(
                        color: Colors.grey.shade300,
                        width: 1,
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(2), // Date
                        1: FlexColumnWidth(1), // Montant
                      },
                      children: [
                        // En-tête
                        TableRow(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(
                                'Date'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(
                                'Montant'.tr(),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        // Lignes de données
                        ...paiements.map((p) {
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(
                                  DateFormat('dd/MM/yyyy').format(p.datePaiement),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Text(
                                  '${p.montant.toStringAsFixed(2)} €',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              // Pagination
              if (totalPages > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: currentPage > 1 ? () => _goToPage(currentPage - 1) : null,
                      ),
                      ...List.generate(totalPages, (index) {
                        final pageNum = index + 1;
                        if (pageNum == 1 ||
                            pageNum == totalPages ||
                            (pageNum >= currentPage - 2 && pageNum <= currentPage + 2)) {
                          return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: currentPage == pageNum ? Colors.blue : Colors.grey[300],
                              foregroundColor: currentPage == pageNum ? Colors.white : Colors.black,
                              minimumSize: const Size(40, 40),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => _goToPage(pageNum),
                            child: Text(pageNum.toString()),
                          );
                        } else if ((pageNum == currentPage - 3 && currentPage > 3) ||
                            (pageNum == currentPage + 3 && currentPage < totalPages - 2)) {
                          return const Text(' … ');
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