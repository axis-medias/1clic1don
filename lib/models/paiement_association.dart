class PaiementAssociation {
  final double montant;
  final DateTime datePaiement;

  PaiementAssociation({required this.montant, required this.datePaiement});

  factory PaiementAssociation.fromJson(Map<String, dynamic> json) {
    return PaiementAssociation(
      montant: (() {
        final value = json['montant'];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      })(),
      datePaiement: DateTime.parse(json['date_paiement']),
    );
  }
}