/// Vínculo entre nutricionista e paciente (documento links/{proUid}_{patientUid}).
///
/// O nutricionista cria o pedido; só o paciente aceita ou recusa. O acesso
/// aos dados vem da lista nutritionistUids no perfil do paciente, que só o
/// paciente altera.
enum LinkStatus {
  pending('Aguardando resposta'),
  accepted('Conectado'),
  declined('Recusado'),
  cancelled('Cancelado'),
  ended('Encerrado');

  const LinkStatus(this.label);

  final String label;

  static LinkStatus parse(Object? v) => LinkStatus.values.firstWhere((s) => s.name == v, orElse: () => LinkStatus.pending);
}

class Link {
  const Link({
    required this.proUid,
    required this.patientUid,
    this.proName = '',
    this.proCrn = '',
    this.patientName = '',
    this.patientEmail = '',
    this.message = '',
    this.status = LinkStatus.pending,
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String proUid;
  final String patientUid;
  final String proName;
  final String proCrn;
  final String patientName;
  final String patientEmail;

  /// Mensagem opcional do nutricionista no pedido.
  final String message;
  final LinkStatus status;
  final String createdAt;
  final String updatedAt;

  static String idFor(String proUid, String patientUid) => '${proUid}_$patientUid';

  String get id => idFor(proUid, patientUid);

  bool get pending => status == LinkStatus.pending;
  bool get accepted => status == LinkStatus.accepted;

  /// Rótulo do paciente para quem o vê no app Pro.
  String get patientLabel => patientName.isNotEmpty ? patientName : patientEmail;

  Link withStatus(LinkStatus s) => Link(
        proUid: proUid,
        patientUid: patientUid,
        proName: proName,
        proCrn: proCrn,
        patientName: patientName,
        patientEmail: patientEmail,
        message: message,
        status: s,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );

  Map<String, dynamic> toJson() => {
        'proUid': proUid,
        'patientUid': patientUid,
        'proName': proName,
        'proCrn': proCrn,
        'patientName': patientName,
        'patientEmail': patientEmail,
        'message': message,
        'status': status.name,
        'createdAt': createdAt.isEmpty ? DateTime.now().toUtc().toIso8601String() : createdAt,
        'updatedAt': updatedAt.isEmpty ? DateTime.now().toUtc().toIso8601String() : updatedAt,
      };

  static Link fromJson(Map<String, dynamic> j) => Link(
        proUid: (j['proUid'] as String?) ?? '',
        patientUid: (j['patientUid'] as String?) ?? '',
        proName: (j['proName'] as String?) ?? '',
        proCrn: (j['proCrn'] as String?) ?? '',
        patientName: (j['patientName'] as String?) ?? '',
        patientEmail: (j['patientEmail'] as String?) ?? '',
        message: (j['message'] as String?) ?? '',
        status: LinkStatus.parse(j['status']),
        createdAt: (j['createdAt'] as String?) ?? '',
        updatedAt: (j['updatedAt'] as String?) ?? '',
      );
}

/// Perfil do nutricionista (documento pros/{uid}).
class ProProfile {
  const ProProfile({this.name = '', this.email = '', this.crn = ''});

  final String name;
  final String email;
  final String crn;

  bool get isComplete => name.trim().isNotEmpty;

  ProProfile copyWith({String? name, String? email, String? crn}) =>
      ProProfile(name: name ?? this.name, email: email ?? this.email, crn: crn ?? this.crn);

  Map<String, dynamic> toJson() =>
      {'name': name, 'email': email, 'crn': crn, 'updatedAt': DateTime.now().toUtc().toIso8601String()};

  static ProProfile fromJson(Map<String, dynamic>? j) => ProProfile(
        name: (j?['name'] as String?) ?? '',
        email: (j?['email'] as String?) ?? '',
        crn: (j?['crn'] as String?) ?? '',
      );
}
