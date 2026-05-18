import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
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

  DonationResult({required this.success, required this.message});
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
  WebViewController? _webViewController;
  late ConfettiController _confettiController;
  // better_player
  BetterPlayerController? _betterPlayerController;

  int _viewCount = 0;
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
  bool _isUnlockContentProcessed = false;
  bool _showSuccessScreen = false;
  bool _isProcessingDonation = false;
  bool _isWebViewReady = false;
  String? deviceId;

  final AuthService _authService = AuthService();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
  GlobalKey<ScaffoldMessengerState>();

  late String _donationType;
  late int _donationId;

  static const int _maxViewPayViews = 3;
  static const int _maxAdmobViews = 20;

  @override
  void initState() {
    super.initState();

    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));

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
      _isWebViewReady = false;
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
          await _checkViewPayQuota();
        }
      } else {
        setState(() {
          _errorMessage = 'error_server'.tr(args: ['${response.statusCode}']);
          _isLoading = false;
        });
        await _checkViewPayQuota();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'error_network'.tr(args: ['$e']);
        _isLoading = false;
      });
      await _checkViewPayQuota();
    }
  }

  void _initializeBetterPlayer() {
    final dataSource = BetterPlayerDataSource.network(_videoUrl!);

    setState(() {
      _betterPlayerController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true, // On garde true pour l'orientation automatique
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
    // Pas besoin de setState supplémentaire pour _isLoading, il est déjà false
  }

  void _onVideoFinished() {
    // Sécurité pour ne pas le déclencher deux fois
    if (_isVideoCompleted || !mounted) return;

    setState(() {
      _isVideoCompleted = true;
      _hasStartedVideo = false;
    });

    // On force la sortie du plein écran pour revenir sur la page et montrer le bouton
    _betterPlayerController?.exitFullScreen();
  }

  void _startVideo() {
    setState(() => _hasStartedVideo = true);
    _initializeBetterPlayer();
  }

  Future<DonationResult> _validateInternalVideoDonation() async {
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
          'device_id': deviceId
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success']) {
          return DonationResult(
            success: true,
            message: data['message'] ?? 'Don validé avec succès',
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
  // VIEWPAY, ADMOB, QUOTA
  // ==================================================================

  Future<void> _checkViewPayQuota() async {
    if (deviceId == null || deviceId!.isEmpty) {
      setState(() {
        _errorMessage = "Identifiant appareil manquant";
        _isLoading = false;
        _isAdmobMode = true;
      });
      await _checkAdmobQuota();
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/check_viewpay.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameParam,
          'device_id': deviceId ?? ''
        }),
      ).timeout(const Duration(seconds: 20), onTimeout: () {
        throw TimeoutException('viewpay_error_timeout_viewpay'.tr());
      });

      debugPrint('check_viewpay: Status ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;

        setState(() {
          _viewCount = data['current_count_viewpay'] ?? 0;
          if (data['success'] == false || data['remaining_viewpay'] == 0) {
            _isAdmobMode = true;
            _checkAdmobQuota();
          } else {
            _initializeWebView();
          }
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'viewpay_error_quota_viewpay'.tr();
          _isLoading = false;
          _isAdmobMode = true;
        });
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('viewpay_error_quota_viewpay'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        await _checkAdmobQuota();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'viewpay_error_quota_viewpay_with_message'.tr(args: ['$e']);
        _isLoading = false;
        _isAdmobMode = true;
      });
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('viewpay_error_quota_viewpay'.tr()),
          backgroundColor: Colors.red,
        ),
      );
      await _checkAdmobQuota();
    }
  }

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
        _errorMessage = 'viewpay_error_quota_admob_with_message'.tr(args: ['$e']);
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
                content: Text(result.message), // ✅ Message précis
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

  // ==================================================================
  // WEBVIEW
  // ==================================================================

  void _initializeWebView() {
    setState(() {
      _isLoading = true;
      _isWebViewReady = false;
    });

    final encodedLibelle = Uri.encodeComponent(widget.libelle ?? 'Don');
    final encodedType = Uri.encodeComponent(_donationType);
    final encodedLang = Uri.encodeComponent(context.locale.languageCode);

    setState(() {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFE8F0FE))
        ..addJavaScriptChannel(
          'flutter_inappwebview',
          onMessageReceived: (JavaScriptMessage message) {
            if (message.message == 'unlockContent' && _isUnlockContentProcessed) {
              return;
            }
            if (message.message.startsWith('error:')) {
              if (mounted) {
                _scaffoldMessengerKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text(
                      'viewpay_error_webview_video'.tr(args: [message.message.substring(6)]),
                    ),
                    duration: const Duration(seconds: 3),
                    backgroundColor: Colors.red,
                  ),
                );
                _reloadWebView();
              }
              return;
            }
            _handleMessage(message.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onWebResourceError: (WebResourceError error) {
              if (error.isForMainFrame == true) {
                if (mounted) {
                  setState(() {
                    _errorMessage = 'viewpay_error_webview_main'.tr();
                    _isLoading = false;
                    _isWebViewReady = false;
                  });
                  _scaffoldMessengerKey.currentState?.showSnackBar(
                    SnackBar(
                      content: Text('viewpay_error_webview_main'.tr()),
                      backgroundColor: Colors.red,
                    ),
                  );
                  _reloadWebView();
                }
              }
            },
            onPageFinished: (url) {
              if (mounted) {
                setState(() {
                  _isWebViewReady = true;
                });
              }
            },
          ),
        )
        ..enableZoom(false)
        ..clearCache()
        ..loadRequest(Uri.parse(
            'https://www.1clic1don.fr/app/viewpay.html?libelle=$encodedLibelle&type=$encodedType&lang=$encodedLang'));
    });

    Future.delayed(const Duration(seconds: 8), () {
      if (_isLoading && !_isWebViewReady && mounted) {
        setState(() {
          _errorMessage = 'viewpay_error_timeout_webview'.tr();
          _isLoading = false;
          _isWebViewReady = false;
        });
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('viewpay_error_timeout_webview'.tr()),
            backgroundColor: Colors.red,
          ),
        );
        _reloadWebView();
      }
    });
  }

  Future<void> _reloadWebView() async {
    if (_webViewController != null) {
      setState(() {
        _isLoading = true;
        _isWebViewReady = false;
        _showSuccessScreen = false;
        _isProcessingDonation = false;
      });

      await _webViewController!.clearCache();
      await _webViewController!.clearLocalStorage();
      if (Platform.isAndroid || Platform.isIOS) {
        await WebViewCookieManager().clearCookies();
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        final encodedLibelle = Uri.encodeComponent(widget.libelle ?? 'Don');
        final encodedType = Uri.encodeComponent(_donationType);
        final encodedLang = Uri.encodeComponent(context.locale.languageCode);
        await _webViewController!.loadRequest(Uri.parse(
            'https://www.1clic1don.fr/app/viewpay.html?libelle=$encodedLibelle&type=$encodedType&lang=$encodedLang'));
      }
    }
  }

  void _handleMessage(String message) {
    if (message == 'unlockContent') {
      setState(() {
        _isUnlockContentProcessed = true;
        _isProcessingDonation = true;
      });

      _callApiToRecordDon().then((result) {
        if (!mounted) return;

        if (result.success) {
          setState(() {
            _showSuccessScreen = true;
          });
          _confettiController.play();
        } else {
          _handleUnlockContentError(
            message: result.message,
            reloadWebView: false,
          );
        }
      }).catchError((e) {
        if (!mounted) return;

        _handleUnlockContentError(
          message: 'Erreur technique inattendue : $e',
          reloadWebView: true,
        );
      }).whenComplete(() {
        if (mounted) {
          setState(() {
            _isProcessingDonation = false;
          });
        }
      });

      return; // ✅ Ajoute ce return pour éviter d'exécuter le switch en dessous
    }

    final scaffoldMessenger = _scaffoldMessengerKey.currentState!;
    switch (message) {
      case 'adsAvailable':
        if (_viewCount < _maxViewPayViews && _webViewController != null) {
          _webViewController!.runJavaScript(
            'document.getElementById("btnShowViewPay").disabled = false;'
                'document.getElementById("btnShowViewPay").textContent = "${'cagnotte_donate_button'.tr()}";',
          );
          setState(() {
            _isLoading = false;
          });
        }
        break;
      case 'noAds':
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('viewpay_no_ads'.tr()),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
            _isAdmobMode = true;
            _checkAdmobQuota();
          });
        }
        break;
    }
  }


  void _handleUnlockContentError({
    required String message,
    bool reloadWebView = false,
  }) {
    debugPrint('ERREUR DON : $message');

    if (mounted) {
      setState(() {
        _isProcessingDonation = false;
      });

      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );

      if (reloadWebView) {
        _reloadWebView();
      }
    }
  }

  Future<DonationResult> _callApiToRecordDon() async {
    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';

      final payload = {
        'id': _donationId,
        'user': usernameParam,
        'origine': 'VIEWPAY',
        'type': _donationType,
        'device_id': deviceId ?? 'unknown'
      };

      debugPrint('=== [DON VIEWPAY] Appel API valide_don.php ===');
      debugPrint('Payload envoyé: ${jsonEncode(payload)}');

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/valide_don.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException('Délai dépassé (20s)');
        },
      );

      debugPrint('Statut HTTP: ${response.statusCode}');
      debugPrint('Body reçu: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          debugPrint('JSON décodé: $data');

          if (data['success'] == true) {
            return DonationResult(
              success: true,
              message: data['message'] ?? 'Don validé avec succès',
            );
          } else {
            // ✅ On récupère le message d'erreur du serveur !
            final errorMsg = data['message'] ?? 'Erreur inconnue du serveur';
            debugPrint('Échec API - Message: $errorMsg');
            return DonationResult(success: false, message: errorMsg);
          }
        } catch (jsonErr) {
          debugPrint('Erreur décodage JSON: $jsonErr');
          return DonationResult(
            success: false,
            message: 'Réponse serveur invalide (JSON malformé)',
          );
        }
      } else {
        return DonationResult(
          success: false,
          message: 'Erreur serveur HTTP ${response.statusCode}',
        );
      }
    } catch (e, stack) {
      debugPrint('EXCEPTION: $e');
      debugPrint('Stack: ${stack.toString().split('\n').take(3).join('\n')}');

      return DonationResult(
        success: false,
        message: 'Erreur réseau : ${e.toString()}',
      );
    }
  }

  Future<DonationResult> _registerAdmobDonation() async {
    try {
      final memberId = await _authService.getMemberId();
      final usernameParam = memberId ?? '';

      final response = await http.post(
        Uri.parse('https://www.1clic1don.fr/app/valide_don.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': _donationId,
          'user': usernameParam,
          'origine': 'ADMOB',
          'type': _donationType,
          'device_id': deviceId ?? ''
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
            message: data['message'] ?? 'Don AdMob validé',
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
      _isWebViewReady = false;
      _showSuccessScreen = false;
      _isProcessingDonation = false;
      _isUnlockContentProcessed = false;
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
      // CAS 1 : La vidéo est terminée -> On affiche le bouton de validation
      if (_isVideoCompleted) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // S'adapte au contenu
              children: [
                // Animation ou Icône avec un effet de douceur
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF689F38).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                      Icons.card_giftcard_rounded, // Icône plus "cadeau/don"
                      size: 80,
                      color: Color(0xFF689F38)
                  ),
                ),
                const SizedBox(height: 32),

                // Titre enthousiaste
                Text(
                  "Génial ! Vous y êtes presque.",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Texte explicatif plus "humain"
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

                // Bouton d'action principal
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

      // CAS 2 : La vidéo n'a pas encore commencé -> Bouton Lancer
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

      // CAS 3 : La vidéo joue (mais techniquement, on est en plein écran au dessus)
      // On garde le player dans l'arbre des widgets pour qu'il ne soit pas "disposed"
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
                      // On change la couleur si ce n'est pas prêt pour donner un indice visuel
                      backgroundColor: _isAdLoaded ? const Color(0xFF689F38) : Colors.grey[400],
                      minimumSize: const Size(double.infinity, 64),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: _isAdLoaded ? 10 : 0,
                    ),
                    onPressed: () {
                      if (_isAdLoaded) {
                        _showRewardedAd();
                      } else {
                        // Si l'utilisateur clique alors que ce n'est pas chargé
                        _loadRewardedAd(); // On force le rechargement
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

    if (_webViewController != null) {
      return _isLoading || !_isWebViewReady
          ? Column(
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
      )
          : WebViewWidget(controller: _webViewController!);
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
    final canMakeAnotherDonation = _viewCount < _maxViewPayViews || _admobCount < _maxAdmobViews;
    return Padding(
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
          FutureBuilder<String?>(
            future: _authService.getPseudo(),
            builder: (context, snapshot) {
              final beneficiaryText = widget.libelle != null
                  ? _donationType == 'cagnotte'
                  ? 'viewpay_beneficiary_cagnotte_2'.tr(args: [widget.libelle!])
                  : 'viewpay_beneficiary_association_2'.tr(args: [widget.libelle!])
                  : _donationType == 'cagnotte'
                  ? 'viewpay_beneficiary_cagnotte_2'.tr(args: ['cagnotte_default_title'.tr()])
                  : 'viewpay_beneficiary_association_2'.tr(args: ['association_default_name'.tr()]);
              return Text(
                snapshot.hasData && snapshot.data != null
                    ? 'viewpay_success_message_with_pseudo'.tr(args: [beneficiaryText, snapshot.data!])
                    : 'viewpay_success_message'.tr(args: [beneficiaryText]),
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              );
            },
          ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showFullScreenVideo = _isInternalVideoMode && _hasStartedVideo;

    return ScaffoldMessenger(
      key: _scaffoldMessengerKey,
      child: Scaffold(
        appBar: showFullScreenVideo
            ? null // Pas d'appBar en mode vidéo
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
        drawer: const AppMenu(currentRoute: '/viewpay'),
        body: Stack(
          children: [
            // ==================================================================
            // 1. VIDÉO EN PLEIN ÉCRAN
            // ==================================================================
            if (showFullScreenVideo)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: _betterPlayerController != null
                      ? BetterPlayer(controller: _betterPlayerController!)
                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            // ==================================================================
            // 2. ÉCRAN PRINCIPAL (hors vidéo)
            // ==================================================================
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

            // ==================================================================
            // 3. BOUTON VALIDER
            // ==================================================================
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
                    onPressed: _validateInternalVideoDonation,
                    child: Text(
                      'viewpay_watch_video'.tr(),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ),

            // ==================================================================
            // 4. CONFETTIS
            // ==================================================================
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