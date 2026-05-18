class Association {
  final int id;
  final String nom;
  final String? logoUrl;
  final String? detailcourt;
  final String? description;
  final String? imageUrl;
  final String? siteUrl;
  final int idcategorie;

  // === NOUVELLES STATS → OPTIONNELLES (pas required) ===
  final double? balance; // Solde actuel
  final double? totalPaid; // Total déjà versé
  final String? shareUrl; // URL de partage
  final String? shareTextKey; // Clé de traduction
  final double? minSoldePourVirement;

  Association({
    required this.id,
    required this.nom,
    this.logoUrl,
    this.detailcourt,
    this.description,
    this.imageUrl,
    this.siteUrl,
    required this.idcategorie,
    // Nouvelles stats → pas required
    this.balance,
    this.totalPaid,
    this.minSoldePourVirement,
    this.shareUrl,
    this.shareTextKey,
  });

  factory Association.fromJson(Map<String, dynamic> json) {
    // SI le JSON est emballé dans "association": { ... }
    if (json.containsKey('association')) {
      json = json['association'] as Map<String, dynamic>;
    }

    return Association(
      id: json['id'] as int? ?? 0,
      nom: json['libelle'] as String? ?? 'Association inconnue',
      logoUrl: json['logo'] as String?,
      detailcourt: json['detailcourt'] as String?,
      description: json['detailcomplet'] as String?,
      imageUrl: json['img'] as String?,
      siteUrl: json['url_site'] as String?,
      idcategorie: json['id_categorie'] as int? ?? 1,

      // Les nouvelles stats → si elles existent, on les prend, sinon null
      balance: json['balance'] is num
          ? (json['balance'] as num).toDouble()
          : null,
      totalPaid: json['total_paid'] is num ? (json['total_paid'] as num)
          .toDouble() : null,
      minSoldePourVirement: json['min_solde_pour_virement'] is num
          ? (json['min_solde_pour_virement'] as num).toDouble()
          : null,
      shareUrl: json['share']?['url'] as String?,
      shareTextKey: json['share']?['text'] as String?,
    );
  }
}