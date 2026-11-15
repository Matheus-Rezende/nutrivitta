/// Configuração da nuvem do NutriVitta. Nenhum destes valores é segredo:
/// todos ficam dentro do app publicado. Veja o passo a passo em CONFIGURACAO.md.
///
/// Dá para preencher aqui ou passar na compilação, por exemplo:
/// flutter build apk --dart-define=FIREBASE_PROJECT_ID=meu-projeto ...
library;

/// ID do cliente OAuth do tipo "Aplicativo da Web" (termina em
/// .apps.googleusercontent.com). Sem ele, o login Google fica desligado.
const kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: _googleWebClientId);
const _googleWebClientId = '1088570032787-0q7drle795jm7ndn3lf8apiog2tvlrct.apps.googleusercontent.com';

/// Chave de API da Web do projeto Firebase.
const kFirebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: _firebaseApiKey);
const _firebaseApiKey = 'AIzaSyCxzbw0rQ-8Uve3J9jSJB_WmbIK98mh0RE';

/// ID do projeto Firebase.
const kFirebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: _firebaseProjectId);
const _firebaseProjectId = 'nutrivitta';
