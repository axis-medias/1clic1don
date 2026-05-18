class DonationArgs {
  final String type; // 'cagnotte' ou 'association'
  final int id;
  final String? libelle; // Nouveau champ pour le nom de la cagnotte/association

  DonationArgs({
    required this.type,
    required this.id,
    this.libelle,
  });

  // Validation pour s'assurer que le type est valide
  bool get isValid => (type == 'cagnotte' || type == 'association') && id > 0;
}