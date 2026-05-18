import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';

class RewardedWebPage extends StatefulWidget {
  final int? cagnotteId;
  final int? associationId;
  final String? libelle;
  final String adUrl;
  final int adId;
  final String? pseudo;
  final String? deviceId;

  const RewardedWebPage({
    super.key,
    this.cagnotteId,
    this.associationId,
    this.libelle,
    required this.adUrl,
    required this.adId,
    this.pseudo,
    this.deviceId,
  });

  @override
  State<RewardedWebPage> createState() => _RewardedWebPageState();
}

class _RewardedWebPageState extends State<RewardedWebPage> with WidgetsBindingObserver {
  WebViewController? _controller;

  final int _durationInSeconds = 15;
  double _progress = 0.0;
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isCompleted = false;
  bool _isLoading = true;
  bool _isValidating = false; // Pour savoir si on est en train de communiquer avec le serveur

  late String _donationType;
  late int _donationId;

  @override
  void initState() {
    super.initState();
    _donationType = widget.cagnotteId != null ? 'cagnotte' : 'association';
    _donationId = widget.cagnotteId ?? widget.associationId!;

    WidgetsBinding.instance.addObserver(this);
    _initWebViewController(); // Direct et simple
  }

  void _initWebViewController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            _startTimer();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.adUrl));

    setState(() {
      _controller = controller;
    });
  }

  void _startTimer() {
    if (_timer != null || _isCompleted) return;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsedSeconds += 100;
        _progress = (_elapsedSeconds / 1000) / _durationInSeconds;
        if (_progress >= 1.0) {
          _progress = 1.0;
          _isCompleted = true;
          _timer?.cancel();
          HapticFeedback.vibrate();
        }
      });
    });
  }

  Future<void> _notifyServer() async {
    setState(() => _isValidating = true); // On lance le chargement
    try {
      await http.post(
        Uri.parse('https://www.1clic1don.fr/app/valide_don_cs.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': _donationId,
          'type': _donationType,
          'user': widget.pseudo ?? '',
          'ad_id': widget.adId.toString(),
          'device_id': widget.deviceId ?? ''
        }),
      ).timeout(const Duration(seconds: 10));

      // Tu peux ajouter un check ici si tu veux être sûr que le PHP a renvoyé success:true
    } catch (e) {
      debugPrint("Erreur Validation Serveur: $e");
    } finally {
      if (mounted) setState(() => _isValidating = false); // On arrête le chargement
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCompleted && !_isLoading) _startTimer();
    }
  }

  void _showExitAfterTimerConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("clicsol_validation_pending_title".tr()), // "Don non validé"
        content: Text("clicsol_validation_pending_content".tr()), // "Le temps est écoulé ! Cliquez sur Valider pour confirmer votre don, sinon il sera perdu."
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // On reste sur la page
            child: Text("clicsol_stay".tr().toUpperCase()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Ferme le dialogue
              Navigator.pop(context); // Quitte la page sans envoyer true
            },
            child: Text("clicsol_exit".tr().toUpperCase(), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // On met canPop à false pour TOUJOURS intercepter le bouton retour
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        if (_isCompleted) {
          // SCÉNARIO A : Le timer est fini mais l'utilisateur n'a pas validé
          _showExitAfterTimerConfirmation();
        } else {
          // SCÉNARIO B : Le timer est encore en cours
          _showExitConfirmation();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.libelle ?? "clicsol_visit_title".tr()),
          leading: CloseButton(onPressed: () {
            // On applique la même logique au bouton "X" de l'AppBar
            if (_isCompleted) {
              _showExitAfterTimerConfirmation();
            } else {
              _showExitConfirmation();
            }
          }),
        ),
        body: Column(
          children: [
            _buildTopBanner(),
            Expanded(
              child: Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!)
                  else
                    const SizedBox.shrink(),

                  if (_isCompleted)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 500),
                        opacity: _isCompleted ? 1.0 : 0.0,
                        child: _buildActionButtons(),
                      ),
                    ),

                  if (_isLoading || _controller == null)
                    const Center(child: CircularProgressIndicator(color: Color(0xFF689F38))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBanner() {
    int remaining = _durationInSeconds - (_elapsedSeconds ~/ 1000);
    if (remaining < 0) remaining = 0;
    return Column(
      children: [
        LinearProgressIndicator(value: _progress, minHeight: 6, valueColor: const AlwaysStoppedAnimation(Color(0xFF689F38))),
        Container(
          color: _isCompleted ? const Color(0xFF689F38) : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_isCompleted ? Icons.check_circle : Icons.hourglass_top, color: _isCompleted ? Colors.white : const Color(0xFF689F38)),
              const SizedBox(width: 10),
              Text(
                _isCompleted ? "clicsol_thanks_ready".tr() : "clicsol_timer_remaining".tr(args: [remaining.toString()]),
                style: TextStyle(fontWeight: FontWeight.bold, color: _isCompleted ? Colors.white : Colors.black87),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return
      // On utilise SafeArea pour éviter que les boutons soient coupés par la barre système
      SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(15, 0, 15, 15),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 15,
                  offset: const Offset(0, -2)
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bouton Sponsor (Gardé et stylisé)
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                onPressed: () => launchUrl(Uri.parse(widget.adUrl), mode: LaunchMode.externalApplication),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 38),
                  backgroundColor: const Color(0xFF1e88e5),
                  foregroundColor: Colors.white,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                label: Text("clicsol_sponsor_site".tr().toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              // Bouton Valider
              ElevatedButton(
                onPressed: _isValidating ? null : () async { // Désactive le bouton pendant le chargement
                  await _notifyServer();
                  if (mounted) Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF689F38),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isValidating
                    ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                )
                    : Text("clicsol_validate_donation".tr().toUpperCase()),
              ),
            ],
          ),
        ),
      );
  }

  void _showExitConfirmation() {
    // 1. On met le timer en pause immédiatement
    _timer?.cancel();
    _timer = null;

    showDialog(
      context: context,
      barrierDismissible: false, // Force l'utilisateur à choisir un bouton
      builder: (context) => AlertDialog(
        title: Text("clicsol_exit_title".tr()),
        content: Text("clicsol_exit_content".tr()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(context); // Ferme le dialog
                // 2. L'utilisateur RESTE : on relance le timer
                _startTimer();
              },
              child: Text("clicsol_stay".tr())
          ),
          TextButton(
              onPressed: () {
                Navigator.pop(context); // Ferme le dialog
                Navigator.pop(context); // Quitte la page (le timer reste arrêté)
              },
              child: Text("clicsol_exit".tr(), style: const TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}