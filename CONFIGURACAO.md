# Configuração da nuvem do NutriVitta

O app precisa de um projeto Firebase próprio (separado do GM Fitness). Tudo aqui cabe no plano gratuito **Spark**, que não pede cartão. Não ative o plano Blaze nem o faturamento. Os nomes dos menus podem variar um pouco no console.

Ao final você terá três valores, nenhum deles secreto:

| Valor | Onde vai |
|---|---|
| ID do cliente da Web (`...apps.googleusercontent.com`) | `GOOGLE_WEB_CLIENT_ID` |
| Chave de API da Web | `FIREBASE_API_KEY` |
| ID do projeto | `FIREBASE_PROJECT_ID` |

## 1. Criar o projeto

1. Acesse https://console.firebase.google.com e crie um projeto (ex.: `nutrivitta`). O Google Analytics pode ficar desligado.
2. Em **Configurações do projeto > Geral**, anote o **ID do projeto**.

## 2. Login com o Google

1. **Authentication > Método de login > Google > Ativar**. Escolha o e-mail de suporte e salve.
2. Abra de novo o provedor Google e, em **Configuração do SDK da Web**, copie o **ID do cliente da Web**.
3. Em **Configurações do projeto > Geral**, copie a **Chave de API da Web** (ela aparece depois que o Authentication é ativado).

## 3. Banco de dados

1. **Firestore Database > Criar banco de dados**, em **modo de produção**, na região `southamerica-east1` (São Paulo).
2. Na aba **Regras**, apague o conteúdo, cole o arquivo [`firestore.rules`](firestore.rules) deste projeto e clique em **Publicar**.

Essas regras garantem que cada pessoa só acessa os próprios dados e que o nutricionista só lê os pacientes que o autorizaram.

## 4. App Android e chave de assinatura

O login Google só funciona em APKs assinados com uma chave cujo SHA-1 esteja cadastrado.

1. Gere uma chave (uma vez só; guarde o arquivo e a senha em local seguro):
   ```
   keytool -genkey -v -keystore nutrivitta.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nutrivitta
   ```
2. Veja o SHA-1 dela:
   ```
   keytool -list -v -keystore nutrivitta.jks -alias nutrivitta
   ```
3. No Firebase, em **Configurações do projeto > Geral > Seus apps > Adicionar app > Android**:
   - Nome do pacote: `com.nutrivitta.nutrivitta`
   - Certificado de assinatura SHA-1: o valor do passo 2
   - Não é preciso baixar o `google-services.json`: o app usa a API REST.
4. Para testar com `flutter run`, cadastre também o SHA-1 da chave de depuração da sua máquina (`~/.android/debug.keystore`, senha `android`, alias `androiddebugkey`).

Para compilar localmente com a chave, crie `android/key.properties` (o arquivo já está no `.gitignore`):
```
storeFile=/caminho/para/nutrivitta.jks
storePassword=SUA_SENHA
keyAlias=nutrivitta
```

## 5. Google Drive

1. Acesse https://console.cloud.google.com e selecione o mesmo projeto.
2. **APIs e serviços > Biblioteca > Google Drive API > Ativar**.
3. **APIs e serviços > Tela de permissão OAuth**: confira nome do app e e-mail de suporte, e adicione o escopo `.../auth/drive.appdata`.
4. Enquanto o app estiver em modo **Teste**, só entram as contas listadas em **Usuários de teste**. Para liberar a todos, publique o app nessa mesma tela.

## 6. Colocar os valores no app

Escolha uma das formas:

- **No código**: preencha as três constantes em `lib/config.dart`.
- **Na compilação**:
  ```
  flutter build apk --release \
    --dart-define=GOOGLE_WEB_CLIENT_ID=... \
    --dart-define=FIREBASE_API_KEY=... \
    --dart-define=FIREBASE_PROJECT_ID=...
  ```
- **No GitHub Actions** (o fluxo `.github/workflows/flutter.yml` já lê estes nomes):
  - Em **Settings > Secrets and variables > Actions > Variables**: `GOOGLE_WEB_CLIENT_ID`, `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`.
  - Em **Secrets**: `ANDROID_KEYSTORE_BASE64` (saída de `base64 -w0 nutrivitta.jks`) e `ANDROID_KEYSTORE_PASSWORD`.

## 7. Conferir

1. Instale o APK, toque em **Entrar com o Google** e crie um perfil de paciente.
2. Em outra conta, crie um perfil de nutricionista e anote o código de convite.
3. No paciente: **Perfil > Nutricionista > Vincular com código**.
4. No nutricionista: puxe a lista de pacientes para atualizar, abra o paciente, defina metas e deixe um recado.
5. No console, em **Firestore Database > Dados**, devem aparecer as coleções `users`, `invites` e `nutritionists`.

Se o app mostrar "A nuvem recusou o acesso", as regras do passo 3 não foram publicadas. Se o login falhar logo após escolher a conta, o SHA-1 ou o ID do cliente da Web está errado.
