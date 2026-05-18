import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:confetti/confetti.dart';
import 'package:http/http.dart' as http;
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:clic_1_don/service/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'app_menu.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/services.dart';
import 'package:clic_1_don/service/device_service.dart';

class DonationResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? badge;

  DonationResult({
    required this.success,
    required this.message,
    this.badge,
  });
}

class DonationPage extends StatefulWidget {
  final int? cagnotteId;
  final int? associationId;
  final String? libelle;

  const DonationPage({
    super.key,
    this.cagnotteId,
    this.associationId,
    this.libelle,
  }) : assert(
  (cagnotteId != null && associationId == null) ||
      (cagnotteId == null && associationId != null),
  'Either cagnotteId or associationId must be provided, but not both.');

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage> {
  late ConfettiController _confettiController;
  BetterPlayerController? _betterPlayerController;

  int _admobCount = 0;
  bool _quotaExceeded = false;
  bool _isAdmobMode = false;
  bool _isInternalVideoMode = false;
  bool _isVideoCompleted = false;
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isLoading = true;
  bool _rewardEarned = false;
  String? _errorMessage;
  String? _videoUrl;
  int? _adId;
  bool _hasStartedVideo = false;
  bool _showSuccessScreen = false;
  bool _isProcessingDonation = false;
  String? deviceId;
  Map<String, dynamic>? _donationBadge;

  final AuthService _authService = AuthService();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
  GlobalKey<ScaffoldMessengerState>();

  late String _donationType;
  late int _donationId;

  static const int _maxAdmobViews = 20;

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

    // Chargement asynchrone du deviceId + démarrage du flux
    _initializeDeviceAndLoadAd();
  }

  Future<void> _initializeDeviceAndLoadAd() async {
    try {
      deviceId = await DeviceService.getPersistentDeviceId();
      print("✅ DonationPage - Device UUID chargé : $deviceId");

      if (deviceId == null || deviceId!.isEmpty) {
        setState(() {
          _errorMessage = "Identifiant appareil manquant";
          _isLoading = false;
        });
        return;
      }

      await _checkInternalVideoAd();
    } catch (e) {
      print("❌ Erreur DeviceService dans DonationPage: $e");
      if (mounted) {
        setState(() {
          _errorMessage = 'Erreur lors de l\'initialisation de l\'appareil';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _betterPlayerController?.dispose();
    _confettiController.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  // ==================================================================
  // API & LOGIQUE
  // ==================================================================

  Future<void> _checkInternalVideoAd() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasStartedVideo = false;
      _isVideoCompleted = false;
      _videoUrl = null;
      _adId = null;
      _isInternalVideoMode = false;
      _showSuccessScreen = false;
      _isProcessingDonation = false;
    });

    _betterPlayerController?.dispose();
    _betterPlayerController = null;

    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/get_internal_video_ad.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user': usernameParam,
          'type': _donationType,
          'id': _donationId,
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data']['url_video_mp4'] != null) {
          setState(() {
            _isInternalVideoMode = true;
            _videoUrl = data['data']['url_video_mp4'];
            _adId = data['data']['id'];
            _isLoading = false;
          });
        } else {
          // ✅ Pas de vidéo interne → Passe directement à AdMob
          await _checkAdmobQuota();
        }
      } else {
        print('❌ get_internal_video_ad.php a retourné ${response.statusCode} pour cagnotte');
        print('   Corps : ${response.body}');
        setState(() {
          _errorMessage = 'error_server'.tr(args: ['${response.statusCode}']);
          _isLoading = false;
        });
        await _checkAdmobQuota();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'error_network'.tr(args: ['$e']);
        _isLoading = false;
      });
      await _checkAdmobQuota();
    }
  }

  void _initializeBetterPlayer() {
    final dataSource = BetterPlayerDataSource.network(_videoUrl!);

    setState(() {
      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          looping: false,
          fit: BoxFit.contain,
          fullScreenByDefault: true,
          allowedScreenSleep: false,
          autoDetectFullscreenAspectRatio: true,
          autoDetectFullscreenDeviceOrientation: true,
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            enableProgressBar: true,
            enableProgressBarDrag: false,
            enablePlayPause: false,
            enableMute: true,
            enableFullscreen: false,
            enableSkips: false,
            showControlsOnInitialize: false,
          ),
          eventListener: (event) {
            if (event.betterPlayerEventType == BetterPlayerEventType.finished) {
              _onVideoFinished();
            }
          },
        ),
        betterPlayerDataSource: dataSource,
      );
    });
  }

  void _onVideoFinished() {
    if (_isVideoCompleted || !mounted) return;

    setState(() {
      _isVideoCompleted = true;
      _hasStartedVideo = false;
    });

    _betterPlayerController?.exitFullScreen();
  }

  void _startVideo() {
    setState(() => _hasStartedVideo = true);
    _initializeBetterPlayer();
  }

  Future<DonationResult> _validateInternalVideoDonation() async {

    final String languageCode = context.locale.languageCode;

    if (!_isVideoCompleted) {
      return DonationResult(
        success: false,
        message: 'viewpay_error_video_incomplete'.tr(),
      );
    }

    if (deviceId == null || deviceId!.isEmpty) {
      return DonationResult(
          success: false,
          message: 'Identifiant appareil manquant, veuillez relancer l\'application'
      );
    }

    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/valide_don.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': _donationId,
          'user': usernameParam,
          'origine': 'INTERNAL',
          'type': _donationType,
          'ad_id': _adId,
          'device_id': deviceId,
          'lang': languageCode,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success']) {
          return DonationResult(
            success: true,
            message: data['message'] ?? 'Don validé avec succès',
            badge: data['badge'],
          );
        } else {
          return DonationResult(
            success: false,
            message: data['message'] ?? 'error_api'.tr(args: ['unknown']),
          );
        }
      } else {
        debugPrint('=== ERREUR HTTP ${response.statusCode} ===');
        return DonationResult(
          success: false,
          message: 'error_server'.tr(args: ['${response.statusCode}']),
        );
      }
    } catch (e) {
      debugPrint('EXCEPTION INTERNAL: $e');
      return DonationResult(
        success: false,
        message: 'error_network'.tr(args: ['$e']),
      );
    }
  }

  // ==================================================================
  // ADMOB & QUOTA
  // ==================================================================

  Future<void> _checkAdmobQuota() async {
    if (deviceId == null || deviceId!.isEmpty) {
      setState(() {
        _errorMessage = "Identifiant appareil manquant";
        _isLoading = false;
        _isAdmobMode = true;
        _quotaExceeded = true;
      });
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text("Erreur d'identification appareil"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isAdmobMode = true;
    });

    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/check_admob.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameParam,
          'device_id': deviceId!,     // maintenant sûr
        }),
      ).timeout(const Duration(seconds: 20), onTimeout: () {
        throw TimeoutException('viewpay_error_timeout_admob'.tr());
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;

        setState(() {
          _admobCount = data['current_count_admob'] ?? 0;
          if (data['success'] == false || _admobCount >= _maxAdmobViews) {
            _quotaExceeded = true;
            _isLoading = false;
            _scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text('viewpay_quota_exceeded'.tr()),
                duration: const Duration(seconds: 5),
              ),
            );
          } else {
            _loadRewardedAd();
          }
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'viewpay_error_quota_admob'.tr();
          _isLoading = false;
          _quotaExceeded = true;
        });
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('viewpay_error_quota_admob'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'error_network'.tr(args: ['$e']); // nouveau message
        _isLoading = false;
      });
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('error_network'.tr()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _loadRewardedAd() async {
    if (Platform.isIOS) {
      final status = await AppTrackingTransparency.requestTrackingAuthorization();
      if (status != TrackingStatus.authorized) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'viewpay_error_tracking_denied'.tr();
          });
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _rewardEarned = false;
    });

    RewardedAd.load(
      adUnitId: _getAdUnitId(),
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) return;
          setState(() {
            _rewardedAd = ad;
            _isAdLoaded = true;
            _isLoading = false;
          });
        },
        onAdFailedToLoad: (error) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _isAdLoaded = false;
            _errorMessage = 'viewpay_error_load_ad'.tr(args: [(error.message)]);
          });
          Future.delayed(const Duration(seconds: 5), _loadRewardedAd);
        },
      ),
    );
  }

  void _showRewardedAd() {
    if (_rewardedAd == null) {
      setState(() {
        _errorMessage = 'viewpay_error_ad_unavailable'.tr();
      });
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (RewardedAd ad) {},
      onAdDismissedFullScreenContent: (ad) async {
        _rewardedAd?.dispose();
        if (!mounted) return;
        setState(() {
          _isAdLoaded = false;
          _rewardedAd = null;
          _isProcessingDonation = true;
        });

        if (_rewardEarned) {
          final result = await _registerAdmobDonation();

          if (!mounted) return;

          if (result.success) {
            setState(() {
              _donationBadge = result.badge;
              _isProcessingDonation = false;
              _showSuccessScreen = true;
            });
            _confettiController.play();
          } else {
            setState(() {
              _isProcessingDonation = false;
            });
            _scaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text(result.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _rewardedAd?.dispose();
        if (!mounted) return;
        setState(() {
          _isAdLoaded = false;
          _rewardedAd = null;
          _isProcessingDonation = false;
          _errorMessage = 'viewpay_error_show_ad'.tr(args: ['$error']);
        });
        _checkAdmobQuota();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        setState(() {
          _rewardEarned = true;
        });
      },
    );
  }

  String _getAdUnitId() {
    if (Platform.isIOS) {
      return 'ca-app-pub-2109564916799886/2094127907';
    } else {
      return 'ca-app-pub-2109564916799886/1172673333';
    }
  }

  Future<DonationResult> _registerAdmobDonation() async {
    final String languageCode = context.locale.languageCode;

    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';
      if (deviceId == null || deviceId!.isEmpty) {
        return DonationResult(
            success: false,
            message: 'Identifiant appareil manquant, veuillez relancer l\'application'
        );
      }
      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/valide_don.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': _donationId,
          'user': usernameParam,
          'origine': 'ADMOB',
          'type': _donationType,
          'device_id': deviceId!,
          'lang': languageCode,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success']) {
          if (mounted) {
            setState(() {
              _admobCount = data['current_count_admob'] ?? _admobCount + 1;
              if (_admobCount >= _maxAdmobViews) {
                _quotaExceeded = true;
              }
            });
          }
          return DonationResult(
            success: true,
            message: data['message'] ?? 'Don ADMOB validé',
            badge: data['badge'],
          );
        } else {
          return DonationResult(
            success: false,
            message: data['message'] ?? 'Erreur lors de la validation AdMob',
          );
        }
      } else {
        return DonationResult(
          success: false,
          message: 'Erreur HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return DonationResult(
        success: false,
        message: 'Erreur réseau AdMob : $e',
      );
    }
  }

  void _makeAnotherDonation() {
    setState(() {
      _isLoading = true;
      _showSuccessScreen = false;
      _isProcessingDonation = false;
    });
    _checkInternalVideoAd();
  }

  void _returnToPreviousScreen() {
    Navigator.pushReplacementNamed(
      context,
      _donationType == 'cagnotte' ? '/liste-cagnottes' : '/decouvrir-associations',
    );
  }

  // ==================================================================
  // WIDGETS
  // ==================================================================

  Widget _buildMainContent() {
    if (_isProcessingDonation) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF689F38)),
          const SizedBox(height: 16),
          Text(
            'viewpay_processing_donation'.tr(),
            style: const TextStyle(fontSize: 16, color: Color(0xFF1e88e5)),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_showSuccessScreen) {
      return _buildSuccessScreen();
    }

    if (_errorMessage != null && _quotaExceeded == false) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFfb8c00),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _checkInternalVideoAd,
              child: Text('error_retry_button'.tr()),
            ),
          ],
        ),
      );
    }

    if (_quotaExceeded) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'viewpay_quota_exceeded'.tr(),
              style: const TextStyle(fontSize: 18, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e88e5),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _returnToPreviousScreen,
              child: Text('voir_associations_back_button'.tr()),
            ),
          ],
        ),
      );
    }

    if (_isInternalVideoMode) {
      if (_isVideoCompleted) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF689F38).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                      Icons.card_giftcard_rounded,
                      size: 80,
                      color: Color(0xFF689F38)
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  "Génial ! Vous y êtes presque.",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black54, fontSize: 16, height: 1.5),
                    children: [
                      const TextSpan(text: "Grâce à votre temps, un don va être reversé à l'association. "),
                      TextSpan(
                        text: "Cliquez ci-dessous pour confirmer votre don",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF689F38).withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF689F38),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        setState(() {
                          _isLoading = true;
                          _isProcessingDonation = true;
                          _hasStartedVideo = false;
                          _isVideoCompleted = false;
                        });

                        final result = await _validateInternalVideoDonation();

                        if (!mounted) return;

                        setState(() {
                          _isLoading = false;
                          _isProcessingDonation = false;
                        });

                        if (result.success) {
                          setState(() {
                            _donationBadge = result.badge;
                            _showSuccessScreen = true;
                          });
                          _confettiController.play();
                        } else {
                          _scaffoldMessengerKey.currentState?.showSnackBar(
                            SnackBar(
                              content: Text(result.message),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: Text(
                        'viewpay_watch_video'.tr(),
                        style: TextStyle(
                          fontSize: 18,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      if (!_hasStartedVideo) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1e88e5), Color(0xFF42a5f5)]),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_donationType == 'cagnotte' ? Icons.savings : Icons.favorite, color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _donationType == 'cagnotte'
                                ? 'clicsol_for_cagnotte'.tr(args: [widget.libelle ?? '...'])
                                : 'clicsol_for_association'.tr(args: [widget.libelle ?? '...']),
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(_donationType == 'cagnotte' ? Icons.savings : Icons.favorite, color: Colors.white, size: 32),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Icon(Icons.card_giftcard, size: 90, color: Color(0xFFfb8c00)),
                  const SizedBox(height: 24),
                  Text(
                    'viewpay_video_prompt'.tr(),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1e88e5)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFfb8c00),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)
                        ),
                      ),
                      onPressed: _startVideo,
                      child: Text(
                        'viewpay_watch_video'.tr(),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Center(
        child: _betterPlayerController != null
            ? AspectRatio(
          aspectRatio: 16 / 9,
          child: BetterPlayer(controller: _betterPlayerController!),
        )
            : const CircularProgressIndicator(),
      );
    }

    if (_isAdmobMode) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1e88e5), Color(0xFF42a5f5)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_donationType == 'cagnotte' ? Icons.savings : Icons.favorite, color: Colors.white, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _donationType == 'cagnotte'
                              ? 'Don pour la cagnotte : ${widget.libelle ?? 'une bonne cause'}'
                              : 'Don pour l\'association : ${widget.libelle ?? 'une bonne cause'}',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(_donationType == 'cagnotte' ? Icons.savings : Icons.favorite, color: Colors.white, size: 32),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                const Icon(Icons.card_giftcard, size: 90, color: Color(0xFFfb8c00)),
                const SizedBox(height: 24),
                Text(
                  'viewpay_video_prompt'.tr(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1e88e5)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                if (_isLoading)
                  Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFF689F38), strokeWidth: 5),
                      SizedBox(height: 16),
                      Text(
                        'chargement-publicite'.tr(),
                        style: TextStyle(fontSize: 16, color: Color(0xFF1e88e5)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                else if (_errorMessage != null)
                  Column(
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 15), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFfb8c00), minimumSize: const Size(double.infinity, 50)),
                        onPressed: _loadRewardedAd,
                        child: Text('error_retry_button'.tr(), style: const TextStyle(fontSize: 16)),
                      ),
                    ],
                  )
                else
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAdLoaded ? const Color(0xFF689F38) : Colors.grey[400],
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: _isAdLoaded ? 10 : 0,
                    ),
                    onPressed: () {
                      if (_isAdLoaded) {
                        _showRewardedAd();
                      } else {
                        _loadRewardedAd();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('chargement-publicite'.tr()),
                              duration: const Duration(seconds: 2)
                          ),
                        );
                      }
                    },
                    child: _isAdLoaded
                        ? Text(
                      'viewpay_watch_video'.tr(),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    )
                        : const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: Color(0xFF689F38)),
        const SizedBox(height: 8),
        Text(
          'viewpay_loading_video'.tr(),
          style: const TextStyle(fontSize: 14, color: Color(0xFF1e88e5)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSuccessScreen() {
    final canMakeAnotherDonation = _admobCount < _maxAdmobViews;
    return SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.card_giftcard,
            size: 60,
            color: Color(0xFF1e88e5),
          ),
          const SizedBox(height: 16),
          Text(
            'viewpay_success_title'.tr(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF28a745),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          FutureBuilder<bool>(
            future: _authService.isTokenValid(),
            builder: (context, tokenSnapshot) {
              final isLoggedIn = tokenSnapshot.data == true;
              return FutureBuilder<String?>(
                future: isLoggedIn ? _authService.getPseudo() : Future.value(null),
                builder: (context, pseudoSnapshot) {
                  final beneficiaryText = widget.libelle != null
                      ? (_donationType == 'cagnotte'
                      ? 'viewpay_beneficiary_cagnotte_2'.tr(args: [widget.libelle!])
                      : 'viewpay_beneficiary_association_2'.tr(args: [widget.libelle!]))
                      : (_donationType == 'cagnotte'
                      ? 'viewpay_beneficiary_cagnotte_2'.tr(args: ['cagnotte_default_title'.tr()])
                      : 'viewpay_beneficiary_association_2'.tr(args: ['association_default_name'.tr()]));
                  final pseudo = pseudoSnapshot.data;
                  return Text(
                    isLoggedIn && pseudo != null
                        ? 'viewpay_success_message_with_pseudo'.tr(args: [beneficiaryText, pseudo])
                        : 'viewpay_success_message'.tr(args: [beneficiaryText]),
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  );
                },
              );
            },
          ),
          if (_donationBadge != null &&
              _donationBadge!['status'] != null)
            _buildDonationBadgeBox(_donationBadge!),
          if (!canMakeAnotherDonation) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                border: Border.all(color: const Color(0xFFFFEEBA)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'viewpay_quota_exceeded_message'.tr(),
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canMakeAnotherDonation)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1e88e5),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _makeAnotherDonation,
                      child: Text(
                        'viewpay_another_donation'.tr(),
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF28a745),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _returnToPreviousScreen,
                    child: Text(
                      'voir_associations_back_button'.tr(),
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildDonationBadgeBox(Map<String, dynamic> badgeData) {
    final status = badgeData['status'];

    if (status == null) {
      return const SizedBox.shrink();
    }

    final bool isNew = badgeData['is_new_status'] == true;

    void showDonationBadgeDialog({
      required String name,
      required String description,
      required String iconUrl,
      required int streak,
    }) {
      showDialog(
        context: context,
        builder: (_) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.network(
                    iconUrl,
                    width: 260,
                    height: 260,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1e88e5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'badge_current_streak'.tr(args: ['$streak']),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFfb8c00),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1e88e5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('close'.tr()),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isNew
              ? [
            const Color(0xFFFFF3CD),
            const Color(0xFFFFE082),
          ]
              : [
            Colors.white,
            const Color(0xFFF5F5F5),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isNew
              ? const Color(0xFFfb8c00)
              : Colors.grey.shade300,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: isNew
                ? const Color(0xFFfb8c00).withValues(alpha: 0.35)
                : Colors.black12,
            blurRadius: isNew ? 25 : 10,
            spreadRadius: isNew ? 2 : 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            isNew
                ? 'new_badge_unlocked'.tr()
                : 'current_badge'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isNew
                  ? const Color(0xFFe65100)
                  : const Color(0xFF1e88e5),
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          TweenAnimationBuilder<double>(
            tween: Tween(begin: isNew ? 0.7 : 1.0, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: GestureDetector(
              onTap: () {
                showDonationBadgeDialog(
                  name: status['name'] ?? '',
                  description: status['description'] ?? '',
                  iconUrl: status['icon'] ?? '',
                  streak: badgeData['streak'] ?? 0,
                );
              },
              child: Image.network(
                status['icon'],
                width: 140,
                height: 140,
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            status['name'] ?? '',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          Text(
            status['description'] ?? '',
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 14),

          Text(
            'badge_current_streak'.tr(
              args: ['${badgeData['streak'] ?? 0}'],
            ),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF689F38),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showFullScreenVideo = _isInternalVideoMode && _hasStartedVideo;

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: showFullScreenVideo
            ? null
            : AppBar(
          title: Text('donate_title'.tr(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          centerTitle: true,
          backgroundColor: const Color(0xFF1e88e5),
          elevation: 4,
          iconTheme: const IconThemeData(color: Colors.white),
          automaticallyImplyLeading: false,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'welcome_menu_tooltip'.tr(),
            ),
          ),
        ),
        drawer: const AppMenu(currentRoute: '/donate'),
        body: Stack(
          children: [
            if (showFullScreenVideo)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: _betterPlayerController != null
                      ? BetterPlayer(controller: _betterPlayerController!)
                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            if (!showFullScreenVideo)
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
                  ),
                ),
                child: _buildMainContent(),
              ),
            if (showFullScreenVideo && _isVideoCompleted)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF689F38),
                      minimumSize: const Size(340, 70),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 20,
                    ),
                    onPressed: () async {
                      setState(() {
                        _isLoading = true;
                        _isProcessingDonation = true;
                        _hasStartedVideo = false;
                        _isVideoCompleted = false;
                      });

                      final result = await _validateInternalVideoDonation();

                      if (!mounted) return;

                      setState(() {
                        _isLoading = false;
                        _isProcessingDonation = false;
                      });

                      if (result.success) {
                        setState(() {
                          _donationBadge = result.badge;
                          _showSuccessScreen = true;
                        });
                        _confettiController.play();
                      } else {
                        _scaffoldMessengerKey.currentState?.showSnackBar(
                          SnackBar(
                            content: Text(result.message),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Text(
                      'viewpay_watch_video'.tr(),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                colors: const [Color(0xFFfb8c00), Color(0xFF1e88e5)],
                numberOfParticles: 50,
              ),
            ),
          ],
        ),
      ),
    );
  }
}