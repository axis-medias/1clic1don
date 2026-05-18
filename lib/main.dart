import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'screens/splash_screen.dart';
import 'screens/liste_cagnottes.dart';
import 'screens/cagnotte.dart';
import 'screens/login.dart';
import 'screens/signup.dart';
import 'screens/dons_membre.dart';
import 'screens/association.dart';
import 'package:clic_1_don/models/association.dart';
import 'screens/home.dart';
import 'screens/profile.dart';
import 'screens/donation.dart'; // ✅
import 'package:upgrader/upgrader.dart';
import 'screens/decouvrir_associations.dart';
import 'screens/voir_associations.dart';
import 'screens/welcome_screen.dart';
import 'service/auth_service.dart';
import 'models/donation_args.dart'; // ✅
import 'screens/settings_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'service/device_service.dart';
import 'screens/recherche_cagnotte_screen.dart';

/// Fonction corrigée pour google_mobile_ads ^6.0.0
Future<void> requestConsentIfNeeded() async {
  final consentInfo = ConsentInformation.instance;
  ConsentRequestParameters params;

  if (!kReleaseMode) {
    final debugSettings = ConsentDebugSettings(
      debugGeography: DebugGeography.debugGeographyEea,
    );
    params = ConsentRequestParameters(consentDebugSettings: debugSettings);
  } else {
    params = ConsentRequestParameters();
  }

  consentInfo.requestConsentInfoUpdate(
    params,
        () async {
      debugPrint("Mise à jour consentement réussie");
      if (await consentInfo.isConsentFormAvailable()) {
        ConsentForm.loadAndShowConsentFormIfRequired((formError) {
          if (formError != null) {
            debugPrint("Erreur formulaire : ${formError.message}");
          } else {
            debugPrint("Consentement UMP collecté avec succès !");
          }
        });
      } else {
        debugPrint("Aucun formulaire requis");
      }
    },
        (FormError error) {
      debugPrint("Erreur requestConsentInfoUpdate : ${error.message}");
    },
  );
}

Future<Map<String, String?>> getAllDeviceIds() async {
  final deviceInfo = DeviceInfoPlugin();
  Map<String, String?> ids = {};

  try {
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      ids = {
        'Modèle': androidInfo.model,
        'Android ID': androidInfo.id,
        'Marque': androidInfo.brand,
        'Fabricant': androidInfo.manufacturer,
        'Version Android': androidInfo.version.release,
        'SDK Version': androidInfo.version.sdkInt.toString(),
      };
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      ids = {
        'Modèle': iosInfo.model,
        'IDFV': iosInfo.identifierForVendor,
        'Nom': iosInfo.name,
        'Système': iosInfo.systemName,
        'Version système': iosInfo.systemVersion,
      };
    }
  } catch (e) {
    print("❌ Erreur lors de la récupération des infos: $e");
  }

  return ids;
}

Future<String?> getAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
}

String getPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}

Future<bool> _isSimulator() async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    final iosInfo = await deviceInfo.iosInfo;
    return !iosInfo.isPhysicalDevice;
  } catch (e) {
    print("Erreur lors de la détection du simulateur : $e");
    return false;
  }
}

// Fonction FCM corrigée
Future<void> initFCM() async {
  try {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 1. Demande les permissions
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      print('❌ Notifications refusées');
      return;
    }

    // 2. Récupère le token FCM
    String? token = await messaging.getToken();
    print("FCM Token initial: $token");

    // 3. Récupère l'identifiant de l'appareil
    String deviceId = await DeviceService.getPersistentDeviceId();
    print("📱 Persistent Device UUID: $deviceId");

    // 4. Récupère toutes les infos de l'appareil
    Map<String, String?> allDeviceInfo = await getAllDeviceIds();

    // Affichez dans la console
    print("══════════════════════════════════════");
    print("📱 Persistent Device UUID: $deviceId");
    print("");
    print("📊 Tous les identifiants de l'appareil :");
    allDeviceInfo.forEach((key, value) {
      print("   • $key: $value");
    });
    print("══════════════════════════════════════");

    // 5. Pour l'AAID (AdMob)
    print("\n⚠️  Pour l'AAID (AdMob) :");
    print("   1. Chargez une pub test AdMob");
    print("   2. Cherchez 'test ads on this device' dans la console");
    print("   3. Copiez l'ID entre guillemets");
    print("   Format attendu: 33BE2250DF435EB (hexadécimal)");

    // 6. Envoie au serveur
    await sendTokenToServer(token, deviceId);

    // 7. Écoute les mises à jour de token
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print("🔄 Nouveau token FCM: $newToken");
      String newDeviceId = await DeviceService.getPersistentDeviceId();
      await sendTokenToServer(newToken, newDeviceId);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📲 Notification cliquée !");
    });

  } catch (e) {
    print("❌ Erreur dans initFCM: $e");
  }
}

Future<void> sendTokenToServer(String? token, String? deviceId) async {
  if (token == null || deviceId == null) return;

  try {
    final authService = AuthService();
    final memberId = await authService.getMemberId();
    final platform = getPlatform();
    final appVersion = await getAppVersion();

    final response = await http.post(
      Uri.parse('https://www.1clic1don.fr/app/register-device.php'),
      body: {
        'device_token': token,
        'device_id': deviceId,
        'platform': platform,
        'app_version': appVersion ?? '',
        'id_membre': ?memberId,
      },
    );

    if (response.statusCode == 200) {
      print("✅ Token enregistré avec succès !");
    } else {
      print("❌ Erreur lors de l'enregistrement du token: ${response.statusCode}");
    }
  } catch (e) {
    print("❌ Erreur dans sendTokenToServer: $e");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Demande consentement
  await requestConsentIfNeeded();
  // 2. Initialisation Mobile Ads
  MobileAds.instance.initialize();

  // 3. Initialisation EasyLocalization
  await EasyLocalization.ensureInitialized();

  // 4. Initialisation Firebase
  await Firebase.initializeApp();

  // 5. Détermination de la route initiale
  String initialRoute = '/splash';
  try {
    final isSimulator = Platform.isIOS && await _isSimulator();
    if (isSimulator) {
      print("SIMULATEUR iOS détecté → bypass AuthService.isTokenValid()");
    } else {
      final authService = AuthService();
      final isTokenValid = await authService.isTokenValid();
      initialRoute = isTokenValid ? '/home' : '/splash';
    }
  } catch (e, s) {
    print("ERREUR AU DÉMARRAGE : $e\n$s");
    initialRoute = '/splash';
  }

  // 6. Configuration UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent, // Nécessaire pour les versions < Android 15
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // 7. Lancement de l'application
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('fr'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('fr'),
      useOnlyLangCode: true,
      child: MyApp(initialRoute: initialRoute),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      title: '1 CLIC 1 DON',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1e88e5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5FAFF),
        platform: TargetPlatform.iOS,
      ),
      // ✅ AJOUTE CECI : Le builder enveloppe toutes les routes
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling, // ✅ Bon conseil de Gemini
          ),
          child: SafeArea(
            top: false,  // AppBar gère le haut
            bottom: true,  // Protège le bas (Android 15)
            maintainBottomViewPadding: true,  // ✅ Bon conseil aussi
            child: child!,
          ),
        );
      },
      initialRoute: initialRoute,
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/welcome': (context) => const WelcomeScreen(),
        '/liste-cagnottes': (context) => const CagnotteListScreen(),
        '/cagnotte': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Cagnotte?;
          return CagnotteDetailScreen(
            cagnotte: args ??
                Cagnotte(
                  id: 0,
                  titre: 'cagnotte_list_title'.tr(),
                  descriptionCourte: 'cagnotte_description_short'.tr(),
                  descriptionLongue: 'cagnotte_description_long'.tr(),
                  imageUrl: '',
                  idCategorie: 1,
                  soldeCurrent: 0.00,
                  objectifMonetaire: 0.00,
                  mode: ''
                ),
          );
        },
        // ✅ CHANGÉ : Route renommée de '/viewpay' → '/donate'
        '/donate': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as DonationArgs?;
          if (args == null || !args.isValid) {
            return Scaffold(
              body: Center(child: Text('error_invalid_args'.tr())),
            );
          }
          return DonationPage( // ✅ CHANGÉ : ViewPayPage → DonationPage
            cagnotteId: args.type == 'cagnotte' ? args.id : null,
            associationId: args.type == 'association' ? args.id : null,
            libelle: args.libelle,
          );
        },
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const SignupScreen(),
        '/dons_membre': (context) => const DonsMembreScreen(),
        '/association': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is Map<String, dynamic>?) {
            final association = args?['association'] as Association?;
            final idCagnotte = args?['idCagnotte'] as int?;
            if (association == null) {
              return Scaffold(
                body: Center(child: Text('error_no_association'.tr())),
              );
            }
            return AssociationDetailScreen(
              association: association,
              idCagnotte: idCagnotte,
            );
          }
          if (args is Association) {
            return AssociationDetailScreen(association: args);
          }
          return Scaffold(
            body: Center(child: Text('error_invalid_args'.tr())),
          );
        },
        '/home': (context) => const HomeScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/decouvrir-associations': (context) => const DecouvrirAssociationsScreen(),
        '/voir-associations': (context) => const VoirAssociationsScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/recherche-cagnottes': (context) => RechercheCagnottesScreen(
          searchTerm: ModalRoute.of(context)!.settings.arguments as String,
        ),
      },
      home: UpgradeWrapper(initialRoute: initialRoute),
    );
  }
}

class CustomUpgraderMessages extends UpgraderMessages {
  @override String get buttonTitleIgnore => 'upgrader_button_ignore'.tr();
  @override String get buttonTitleLater => 'upgrader_button_later'.tr();
  @override String get buttonTitleUpdate => 'upgrader_button_update'.tr();
  @override String get prompt => 'upgrader_prompt'.tr();
  @override String get title => 'upgrader_title'.tr();
}

class UpgradeWrapper extends StatefulWidget {
  final String initialRoute;
  const UpgradeWrapper({super.key, required this.initialRoute});

  @override
  State<UpgradeWrapper> createState() => _UpgradeWrapperState();
}

class _UpgradeWrapperState extends State<UpgradeWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initFCM();
    });
  }

  @override
  Widget build(BuildContext context) {
    return UpgradeAlert(
      showIgnore: false,
      showLater: false,
      barrierDismissible: false,
      shouldPopScope: () => false,
      dialogStyle: UpgradeDialogStyle.material,
      upgrader: Upgrader(
        languageCode: context.locale.languageCode,
        messages: CustomUpgraderMessages(),
        debugLogging: true,
        durationUntilAlertAgain: const Duration(seconds: 0),
        debugDisplayAlways: false,
      ),
      child: _getInitialScreen(),
    );
  }

  Widget _getInitialScreen() {
    switch (widget.initialRoute) {
      case '/home':
        return const HomeScreen();
      case '/splash':
      default:
        return const SplashScreen();
    }
  }
}