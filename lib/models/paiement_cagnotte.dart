class Preuve {
  final String fichier;
  final DateTime dateUpload;

  Preuve({required this.fichier, required this.dateUpload});

  factory Preuve.fromJson(Map<String, dynamic> json) {
    return Preuve(
      fichier: json['fichier'],
      dateUpload: DateTime.parse(json['date_upload']),
    );
  }
}

class PaiementCagnotte {
  final int id;
  final double montant;
  final DateTime dateDemande;
  final List<Preuve> preuves;

  PaiementCagnotte({
    required this.id,
    required this.montant,
    required this.dateDemande,
    required this.preuves,
  });

  factory PaiementCagnotte.fromJson(Map<String, dynamic> json) {
    return PaiementCagnotte(
      id: json['id'],
      montant: (() {
        final value = json['montant'];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      })(),
      dateDemande: DateTime.parse(json['date_demande']),
      preuves: (json['preuves'] as List).map((p) => Preuve.fromJson(p)).toList(),
    );
  }
}