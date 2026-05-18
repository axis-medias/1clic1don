import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:easy_localization/easy_localization.dart';
import 'app_menu.dart';
import 'package:clic_1_don/service/auth_service.dart';

class DonsMembreScreen extends StatefulWidget {
  const DonsMembreScreen({super.key});
  @override
  State<DonsMembreScreen> createState() => _DonsMembreScreenState();
}

class _DonsMembreScreenState extends State<DonsMembreScreen> {
  final _authService = AuthService();
  String? _userId;
  bool _isLoading = true;
  String? _errorMessage;
  Future<List<dynamic>>? _donsFuture;

  @override
  void initState() {
    super.initState();
    _donsFuture = _fetchDons();
  }

  Future<List<dynamic>> _fetchDons() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      _userId = await _authService.getMemberId();
      final jwt = await _authService.getJwt();
      if (_userId == null || jwt == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'auth_error'.tr();
          });
          Navigator.pushReplacementNamed(context, '/login');
        }
        return [];
      }
      final url = Uri.parse('https://www.1clic1don.fr/app/dons_membre.php');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return data['dons'] as List<dynamic>? ?? [];
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = context.tr(data['message'] ?? 'don_fetch_error'.tr());
          });
        }
        return [];
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'error_network'.tr(args: [e.toString()]);
        });
      }
      return [];
    }
  }

  String _formatDate(String date) {
    try {
      final dateTime = DateTime.parse(date);
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'dons_membre_unknown_date'.tr();
    }
  }

  Future<void> _handlePop() async {
    final isValid = await _authService.isTokenValid();
    if (!mounted) return;
    if (!isValid) {
      Navigator.of(context).pushReplacementNamed('/splash');
    }
  }

  @override
  Widget build(BuildContext context) {
    final double padding = MediaQuery.of(context).size.width < 600 ? 8.0 : 12.0; // Padding dynamique
    final double bottomPadding = MediaQuery.of(context).padding.bottom; // Padding système

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handlePop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'dons_membre_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          backgroundColor: const Color(0xFF1e88e5),
          centerTitle: true,
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
        ),
        drawer: const AppMenu(currentRoute: '/dons_membre'),
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
                : _errorMessage != null
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _donsFuture = _fetchDons();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1e88e5),
                      foregroundColor: Colors.white,
                    ),
                    child: Text('error_retry_button'.tr()),
                  ),
                ],
              ),
            )
                : FutureBuilder<List<dynamic>>(
              future: _donsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('error_generic'.tr(args: [snapshot.error.toString()])));
                } else if (snapshot.hasData) {
                  final dons = snapshot.data!;
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + bottomPadding + 40.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'dons_membre_details_title'.tr(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2c3e50),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        dons.isEmpty
                            ? Center(
                          child: Text(
                            'dons_membre_no_dons'.tr(),
                            style: const TextStyle(fontSize: 16, color: Color(0xFF7f8c8d)),
                            textAlign: TextAlign.center,
                          ),
                        )
                            : Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListView.separated(
                            shrinkWrap: true, // Permet au ListView de s'adapter à son contenu
                            physics: const NeverScrollableScrollPhysics(), // Désactive le défilement interne
                            itemCount: dons.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final don = dons[index];
                              final date = don['date_don']?.toString() ?? 'dons_membre_unknown_date'.tr();
                              final destinataire = don['association_nom']?.toString() ??
                                  don['cagnotte_nom']?.toString() ??
                                  'dons_membre_unknown_recipient'.tr();
                              return ListTile(
                                leading: Text(
                                  _formatDate(date),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFFfb8c00),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                title: Text(
                                  destinataire,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Center(child: Text('dons_membre_no_data'.tr()));
              },
            ),
          ),
      ),
    );
  }
}