import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/scheduler.dart';
import 'app_menu.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedLanguage = 'fr'; // Langue par défaut

  @override
  void initState() {
    super.initState();
    // Récupérer la langue actuelle après le rendu initial
    SchedulerBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _selectedLanguage = context.locale.languageCode;
      });
      debugPrint('SettingsScreen: Initial locale: ${context.locale.languageCode}');
    });
  }

  Future<void> _changeLanguage(String languageCode) async {
    await context.setLocale(Locale(languageCode));
    setState(() {
      _selectedLanguage = languageCode;
    });
    debugPrint('SettingsScreen: Changed locale to: $languageCode');

    // Forcer la reconstruction de l'application entière
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/welcome'); // ou '/splash' selon ta logique
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double padding = isMobile ? 16.0 : 24.0;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'settings_title'.tr(),
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
      drawer: const AppMenu(currentRoute: '/settings'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F0FE), Color(0xFFF5F6F5)],
          ),
        ),
        child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding,
              padding,
              padding,
              padding + bottomPadding + 40.0, // Marge propre au-dessus de la barre système
            ),
            children: [
              Text(
                'settings_language'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2c3e50),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language, color: Color(0xFF1e88e5)),
                      title: Text('language_french'.tr()),
                      trailing: _selectedLanguage == 'fr'
                          ? const Icon(Icons.check, color: Color(0xFF1e88e5))
                          : null,
                      onTap: () => _changeLanguage('fr'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.language, color: Color(0xFF1e88e5)),
                      title: Text('language_english'.tr()),
                      trailing: _selectedLanguage == 'en'
                          ? const Icon(Icons.check, color: Color(0xFF1e88e5))
                          : null,
                      onTap: () => _changeLanguage('en'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24), // un peu d'espace
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip, color: Color(0xFF1e88e5)),
                  title: Text('settings_privacy_options'.tr()), // tu vas ajouter cette clé dans tes traductions
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    // Ouvre à nouveau le formulaire de consentement Google
                    final consentInfo = ConsentInformation.instance;

                    // Vérifie si le bouton doit être affiché (Google le demande seulement si required)
                    final status = await consentInfo.getPrivacyOptionsRequirementStatus();
                    if (status == PrivacyOptionsRequirementStatus.required) {
                      ConsentForm.showPrivacyOptionsForm((formError) {
                        if (formError != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Erreur : ${formError.message}")),
                          );
                        }
                      });
                    } else {
                      // Si pas "required", on peut quand même forcer l'affichage (c'est safe)
                      ConsentForm.showPrivacyOptionsForm((_) {});
                    }
                  },
                ),
              ),
            ],
          ),
      ),
    );
  }
}