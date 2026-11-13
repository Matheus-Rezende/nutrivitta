# Configuração da nuvem do NutriVitta

Os dois apps usam o mesmo projeto Firebase, no plano gratuito **Spark**, que não pede cartão. Não ative o plano Blaze nem o faturamento. Os nomes dos menus podem variar um pouco no console.

## Já feito (13/11/2026)

- Projeto **`nutrivitta`** criado (sem Analytics e sem Gemini).
- **Authentication > Google** ativado, com o e-mail de suporte `cdf30000@gmail.com`.
- **Firestore** criado em `southamerica-east1` (São Paulo), no modo produção.
- **Google Drive API** ativada no Google Cloud.

Valores do projeto (nenhum é secreto):

| Valor | Onde vai | Conteúdo |
|---|---|---|
| ID do cliente da Web | `GOOGLE_WEB_CLIENT_ID` | `1088570032787-0q7drle795jm7ndn3lf8apiog2tvlrct.apps.googleusercontent.com` |
| ID do projeto | `FIREBASE_PROJECT_ID` | `nutrivitta` |
| Chave de API da Web | `FIREBASE_API_KEY` | Google Cloud > APIs e serviços > Credenciais > "Browser key (auto created by Firebase)" > Exibir chave |

## Falta fazer

### 1. Publicar as regras do banco

Firestore Database > **Regras**: apague o conteúdo, cole o arquivo [`firestore.rules`](firestore.rules) e clique em **Publicar**. Sem isso o app mostra "A nuvem recusou o acesso".

### 2. Chave de assinatura

O login Google só funciona em APKs assinados com uma chave cujo SHA-1 esteja cadastrado. Uma chave serve para os dois apps.

1. Gere a chave (uma vez só; guarde o arquivo e a senha em local seguro):
   ```
   keytool -genkey -v -keystore nutrivitta.jks -keyalg RSA -keysize 2048 -validity 10000 -alias nutrivitta
   ```
2. Veja o SHA-1:
   ```
   keytool -list -v -keystore nutrivitta.jks -alias nutrivitta
   ```

### 3. Registrar os dois apps Android

Em **Configurações do projeto > Geral > Seus apps > Adicionar app > Android**, duas vezes:

| Nome do pacote | Apelido |
|---|---|
| `com.nutrivitta.paciente` | NutriVitta |
| `com.nutrivitta.pro` | NutriVitta Pro |

Em cada um, informe o SHA-1 do passo 2. Não é preciso baixar o `google-services.json`: os apps usam a API REST. Para testar com `flutter run`, cadastre também o SHA-1 da chave de depuração da sua máquina (`~/.android/debug.keystore`, senha `android`, alias `androiddebugkey`).

### 4. Tela de permissão do Google

Google Cloud > **APIs e serviços > Tela de permissão OAuth**:
- confira o nome do app e o e-mail de suporte;
- adicione o escopo `.../auth/drive.appdata` (cópia no Drive do paciente);
- enquanto estiver em modo **Teste**, só entram as contas em **Usuários de teste** (até 100). Para liberar a todos, publique o app nessa tela.

### 5. Valores no GitHub

No repositório, **Settings > Secrets and variables > Actions**:
- **Variables**: `GOOGLE_WEB_CLIENT_ID`, `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`.
- **Secrets**: `ANDROID_KEYSTORE_BASE64` (saída de `base64 -w0 nutrivitta.jks`) e `ANDROID_KEYSTORE_PASSWORD`.

O fluxo `.github/workflows/flutter.yml` gera os dois APKs com esses valores. Para compilar na sua máquina, crie `apps/<app>/android/key.properties` (já está no `.gitignore`):
```
storeFile=/caminho/para/nutrivitta.jks
storePassword=SUA_SENHA
keyAlias=nutrivitta
```

## Conferir

1. Instale o **NutriVitta** com uma conta Google e faça o cadastro de paciente.
2. Instale o **NutriVitta Pro** com outra conta, crie o perfil e toque em **Adicionar paciente** com o e-mail da primeira conta.
3. No NutriVitta, o pedido aparece no topo do diário (e vira notificação em até ~15 min com o app fechado). Aceite.
4. No Pro, puxe a lista para atualizar e abra o paciente: diário, resumo, medidas, anamnese, metas e recado.
5. No console, em **Firestore Database > Dados**, devem aparecer `users`, `directory`, `pros` e `links`.

Se o login falhar logo após escolher a conta, o SHA-1 ou o ID do cliente da Web está errado.
