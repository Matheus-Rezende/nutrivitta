/// Configuração da nuvem do NutriVitta. Nenhum destes valores é segredo:
/// todos ficam dentro do app publicado. Veja o passo a passo em CONFIGURACAO.md.
///
/// Dá para preencher aqui ou passar na compilação, por exemplo:
/// flutter build apk --dart-define=FIREBASE_PROJECT_ID=meu-projeto ...
library;

/// Chave de API da Web do projeto Firebase.
const kFirebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: _firebaseApiKey);
const _firebaseApiKey = 'AIzaSyCxzbw0rQ-8Uve3J9jSJB_WmbIK98mh0RE';

/// ID do projeto Firebase.
const kFirebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: _firebaseProjectId);
const _firebaseProjectId = 'nutrivitta';
