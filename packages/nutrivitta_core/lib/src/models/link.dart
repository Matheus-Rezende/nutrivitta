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
    this.anamnesisRequest = '',
    this.anamnesisRequestedAt = '',
    this.anamnesisAnsweredAt = '',
    this.anamnesisUntil = 0,
    this.changeWhat = '',
    this.changeAt = '',
  });

  /// Último dado do paciente alterado pelo nutricionista ('goals',
  /// 'measures', 'anamnesis' ou 'comments') e quando (ISO 8601). O app do
  /// paciente já consulta o vínculo a cada poucos segundos; quando este
  /// campo muda, ele busca os dados de novo.
  final String changeWhat;
  final String changeAt;

  /// Campos que avisam o paciente de uma alteração do nutricionista.
  static Map<String, dynamic> changeFields(String what) =>
      {'changeWhat': what, 'changeAt': DateTime.now().toUtc().toIso8601String()};

  /// Texto do aviso ao paciente para cada tipo de alteração.
  String get changeLabel => switch (changeWhat) {
        'goals' => 'atualizou suas metas',
        'measures' => 'atualizou suas medidas',
        'anamnesis' => 'atualizou sua anamnese',
        'comments' => 'atualizou um recado',
        _ => 'atualizou seus dados',
      };

  /// Pedido do nutricionista para editar a anamnese:
  /// '' (nenhum), 'pending', 'granted' ou 'denied'.
  final String anamnesisRequest;
  final String anamnesisRequestedAt;
  final String anamnesisAnsweredAt;

  /// Até quando (milissegundos desde 1970) o nutricionista pode editar a
  /// anamnese. As regras do banco conferem este campo.
  final int anamnesisUntil;

  /// Por quanto tempo vale a permissão concedida pelo paciente.
  static const anamnesisGrant = Duration(hours: 24);

  bool get anamnesisPending => accepted && anamnesisRequest == 'pending';

  bool get canEditAnamnesis => accepted && anamnesisUntil > DateTime.now().millisecondsSinceEpoch;

  DateTime? get anamnesisUntilTime =>
      anamnesisUntil <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(anamnesisUntil);

  /// Campos do pedido de edição (para gravar só eles).
  Map<String, dynamic> anamnesisFields() => {
        'anamnesisRequest': anamnesisRequest,
        'anamnesisRequestedAt': anamnesisRequestedAt,
        'anamnesisAnsweredAt': anamnesisAnsweredAt,
        'anamnesisUntil': anamnesisUntil,
        'updatedAt': updatedAt,
      };

  Link copyWith({
    LinkStatus? status,
    String? anamnesisRequest,
    String? anamnesisRequestedAt,
    String? anamnesisAnsweredAt,
    int? anamnesisUntil,
  }) =>
      Link(
        proUid: proUid,
        patientUid: patientUid,
        proName: proName,
        proCrn: proCrn,
        patientName: patientName,
        patientEmail: patientEmail,
        message: message,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        anamnesisRequest: anamnesisRequest ?? this.anamnesisRequest,
        anamnesisRequestedAt: anamnesisRequestedAt ?? this.anamnesisRequestedAt,
        anamnesisAnsweredAt: anamnesisAnsweredAt ?? this.anamnesisAnsweredAt,
        anamnesisUntil: anamnesisUntil ?? this.anamnesisUntil,
        changeWhat: changeWhat,
        changeAt: changeAt,
      );

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
  String get patientLabel => patientName.isNotEmpty ? patientName : 'Paciente';

  Link withStatus(LinkStatus s) => copyWith(status: s);

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
        'anamnesisRequest': anamnesisRequest,
        'anamnesisRequestedAt': anamnesisRequestedAt,
        'anamnesisAnsweredAt': anamnesisAnsweredAt,
        'anamnesisUntil': anamnesisUntil,
        'changeWhat': changeWhat,
        'changeAt': changeAt,
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
        anamnesisRequest: (j['anamnesisRequest'] as String?) ?? '',
        anamnesisRequestedAt: (j['anamnesisRequestedAt'] as String?) ?? '',
        anamnesisAnsweredAt: (j['anamnesisAnsweredAt'] as String?) ?? '',
        anamnesisUntil: j['anamnesisUntil'] is num ? (j['anamnesisUntil'] as num).toInt() : 0,
        changeWhat: (j['changeWhat'] as String?) ?? '',
        changeAt: (j['changeAt'] as String?) ?? '',
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
