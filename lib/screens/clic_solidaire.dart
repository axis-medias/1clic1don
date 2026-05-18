import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:confetti/confetti.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'rewarded_webpage.dart'; // On garde l'autre fichier pour la partie WebView
import 'package:clic_1_don/service/device_service.dart';

class ClicSolidairePage extends StatefulWidget {
  final int? cagnotteId;
  final int? associationId;
  final String? libelle;

  const ClicSolidairePage({
    super.key,
    this.cagnotteId,
    this.associationId,
    this.libelle,
  });

  @override
  State<ClicSolidairePage> createState() => _ClicSolidairePageState();
}

class _ClicSolidairePageState extends State<ClicSolidairePage> {
  late ConfettiController _confettiController;
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _isCSAdFound = false;
  bool _showSuccessScreen = false;
  String? _adUrl;
  int? _adId;
  String? deviceId;
  String? _errorMessage;
  String? _userPseudo;
  late String _donationType;
  late int _donationId;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    if (widget.cagnotteId != null) {
      _donationType = 'cagnotte';
      _donationId = widget.cagnotteId!;
    } else if (widget.associationId != null) {
      _donationType = 'association';
      _donationId = widget.associationId!;
    } else {
      setState(() {
        _errorMessage = 'viewpay_error_invalid_id'.tr();
        _isLoading = false;
      });
      return;
    }
    // Chargement sécurisé du deviceId + démarrage de la séquence
    _initializeDeviceAndSequence();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _initializeDeviceAndSequence() async {
    try {
      deviceId = await DeviceService.getPersistentDeviceId();
      print("✅ ClicSolidairePage - Device UUID chargé : $deviceId");

      _userPseudo = await _authService.getPseudo();
      await _checkForAd();
    } catch (e) {
      print("❌ Erreur initialisation ClicSolidairePage: $e");
      setState(() {
        _errorMessage = "Erreur lors de l'initialisation de l'appareil";
        _isLoading = false;
      });
    }
  }

  // Vérifie si une "Visite Solidaire" est dispo sur ton PHP
  Future<void> _checkForAd() async {
    setState(() {
      _isLoading = true;
      _isCSAdFound = false;
      _errorMessage = null;
    });

    // Garde de sécurité renforcée
    if (deviceId == null || deviceId!.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage = "Identifiant appareil manquant, veuillez relancer l'application";
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final memberId = await _authService.getMemberId();

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/get_cs_ad.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user': memberId ?? '',
          'device_id': deviceId!,
          'type': _donationType,
          'id': _donationId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _isCSAdFound = true;
            _adUrl = data['data']['url'];
            _adId = data['data']['id'];
          });
        }
        // Sinon : pas de pub disponible → on reste sur _isCSAdFound = false
      } else {
        _errorMessage = "clicsol_error_network".tr();
      }
    } catch (e) {
      _errorMessage = "clicsol_error_network".tr();
      print("Erreur _checkForAd: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startRewardedVisit() async {
    if (_adUrl == null || _adId == null || deviceId == null) {
      if (mounted) {
        setState(() {
          _errorMessage = "Données de publicité incomplètes";
        });
      }
      return;
    }

    final success = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => RewardedWebPage(
          cagnotteId: widget.cagnotteId,
          associationId: widget.associationId,
          libelle: widget.libelle,
          adUrl: _adUrl!,
          adId: _adId!,
          pseudo: _userPseudo,
          deviceId: deviceId,
        ),
      ),
    );

    if (success == true && mounted) {
      setState(() {
        _showSuccessScreen = true;
        _isCSAdFound = false;
      });
      _confettiController.play();
      _checkForAd();        // Recherche automatique suivante
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("clicsol_visit_title".tr())),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: _buildBodyContent(),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false, // Ne boucle pas, se joue une fois
              // On utilise les couleurs orange et bleu de tes vidéos, ou un mix avec ton vert
              colors: const [
                Color(0xFFfb8c00), // Orange
                Color(0xFF1e88e5), // Bleu
                Color(0xFF689F38), // Ton vert solidaire
              ],
              numberOfParticles: 50, // Plus de particules pour un effet plus riche
              gravity: 0.1, // Les confettis tombent doucement
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent() {

    if (_showSuccessScreen) {
      return _buildSuccessScreen();
    }

    if (_isLoading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF689F38)),
          const SizedBox(height: 20),
          Text("clicsol_loading".tr()),
        ],
      );
    }
// Affiche l'erreur si elle existe
    if (_errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 60),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _checkForAd, // Bouton pour réessayer
            child: Text("error_retry_button".tr()),
          ),
        ],
      );
    }

    if (!_isCSAdFound) {
      return _buildNoAdUI();
    }

    final String donationType = widget.cagnotteId != null ? 'cagnotte' : 'association';

    // Cas où on a trouvé une pub
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. BANDEAU DE DESTINATION (Style Vidéo)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1e88e5), Color(0xFF42a5f5)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(donationType == 'cagnotte' ? Icons.savings : Icons.favorite, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  donationType == 'cagnotte'
                      ? 'clicsol_for_cagnotte'.tr(args: [widget.libelle ?? '...'])
                      : 'clicsol_for_association'.tr(args: [widget.libelle ?? '...']),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              Icon(donationType == 'cagnotte' ? Icons.savings : Icons.favorite, color: Colors.white, size: 28),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // 2. ICONE CENTRALE (Style Clic Solidaire)
        const Icon(Icons.ads_click, size: 90, color: Color(0xFF689F38)),
        const SizedBox(height: 24),

        // 3. TEXTES D'INVITATION
        Text(
          "clicsol_ad_available_title".tr(), // "Une visite solidaire est disponible !"
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1e88e5)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            "clicsol_ad_instruction".tr(), // "En visitant le site... pendant 15s..."
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
          ),
        ),

        const SizedBox(height: 40),

        // 4. BOUTON D'ACTION (Style Vidéo mais couleur Verte)
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF689F38),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            // On ajoute du padding interne pour que le texte ne colle pas aux bords
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 8,
          ),
          onPressed: _startRewardedVisit,
          child: FittedBox(
            fit: BoxFit.scaleDown, // Réduit la taille si c'est trop large
            child: Text(
              'Regarder_clic_solidaire'.tr().toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessScreen() {
    final beneficiaryText = widget.libelle ?? (widget.cagnotteId != null ? 'cagnotte'.tr() : 'association'.tr());
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 80, color: Color(0xFF28a745)),
          const SizedBox(height: 16),
          Text(
            'viewpay_success_title'.tr(),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF28a745)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Message de remerciement (Pseudo + Association)

        Text(
        _userPseudo != null
        ? 'viewpay_success_message_with_pseudo'.tr(args: [beneficiaryText, _userPseudo!])
            : 'viewpay_success_message'.tr(args: [beneficiaryText]),
        style: const TextStyle(fontSize: 18),
        textAlign: TextAlign.center,
        ),

          const SizedBox(height: 30),
          const Divider(),
          const SizedBox(height: 20),

          // --- ZONE DYNAMIQUE : Recherche de la pub suivante ---
          if (_isLoading) ...[
            const CircularProgressIndicator(color: Color(0xFF689F38)),
            const SizedBox(height: 10),
            Text("Recherche d'une nouvelle visite...", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
          ] else if (_isCSAdFound) ...[
            Text("Bonne nouvelle ! Une autre visite est disponible.", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: () {
                _confettiController.stop();
                setState(() => _showSuccessScreen = false);
                _startRewardedVisit(); // On relance directement
              },
              icon: const Icon(Icons.redeem),
              label: Text("FAIRE UN NOUVEAU DON"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e88e5),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ] else ...[
            // Cas où _isLoading est false et _isCSAdFound est false
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(height: 8),
            Text(
              "Plus de publicité disponible pour aujourd'hui.\nMerci pour votre générosité !",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],

          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('voir_associations_back_button'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildNoAdUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sentiment_dissatisfied, size: 80, color: Colors.grey),
        const SizedBox(height: 20),
        Text("clicsol_no_ad_title".tr(), textAlign: TextAlign.center),
        const SizedBox(height: 30),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text("clicsol_back_home".tr()),
        ),
      ],
    );
  }
}